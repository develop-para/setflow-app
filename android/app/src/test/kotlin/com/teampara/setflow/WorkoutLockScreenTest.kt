package com.teampara.setflow

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@LooperMode(LooperMode.Mode.PAUSED)
class WorkoutLockScreenTest {
    private lateinit var context: Context
    private val controllers = mutableListOf<ServiceController<RestTimerService>>()

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("setflow_lock_screen_workout", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences(RestTimerService.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().clear().commit()
    }

    @After
    fun tearDown() {
        WorkoutLockScreenStore.clear(context)
        controllers.forEach { it.destroy() }
        RestTimerService.onAppVisibilityChanged(false)
    }

    @Test
    fun completionDurablyRecordsVisibleValuesAndAdvancesOnlyTheCurrentSet() {
        WorkoutLockScreenStore.publish(context, projection())
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-2"))

        val receipt = WorkoutLockScreenStore.complete(context, "session-1", "token-1")!!

        assertEquals(40.0, receipt.getJSONObject("set").getDouble("weight"), 0.0)
        assertEquals(10, receipt.getJSONObject("set").getInt("reps"))
        assertEquals("entry-bench", receipt.getJSONObject("set").getString("exerciseEntryId"))
        assertEquals("token-2", WorkoutLockScreenStore.currentSet(context)!!.getString("token"))
        // A new Context reads the committed receipt; no Flutter engine is involved.
        val reopened = context.createPackageContext(context.packageName, 0)
        assertEquals(1, WorkoutLockScreenStore.readEvents(reopened).size)
        assertNull(WorkoutLockScreenStore.complete(reopened, "session-1", "token-1"))
        assertEquals(1, WorkoutLockScreenStore.readEvents(reopened).size)
    }

    @Test
    fun aSavedRestDeadlineBlocksAnotherCompletionAndCanBeExtendedOrEnded() {
        WorkoutLockScreenStore.publish(context, projection(restSeconds = 60))
        val receipt = WorkoutLockScreenStore.complete(context, "session-1", "token-1")!!
        val deadline = receipt.getLong("restEndsAtMillis")
        assertTrue(deadline > System.currentTimeMillis())
        assertEquals(deadline, WorkoutLockScreenStore.restEndsAt(context))
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-2"))
        WorkoutLockScreenStore.setRestEndsAt(context, deadline + 30_000L)
        assertEquals(deadline + 30_000L, WorkoutLockScreenStore.restEndsAt(context))
        WorkoutLockScreenStore.setRestEndsAt(context, 0L)
        assertNotNull(WorkoutLockScreenStore.complete(context, "session-1", "token-2"))
    }

    @Test
    fun clearingAndChangingAccountNeverDeletesUnacknowledgedPerformedRecords() {
        WorkoutLockScreenStore.publish(context, projection())
        val first = WorkoutLockScreenStore.complete(context, "session-1", "token-1")!!
        WorkoutLockScreenStore.clear(context)
        assertNull(WorkoutLockScreenStore.currentSet(context))
        assertEquals(1, WorkoutLockScreenStore.readEvents(context).size)
        WorkoutLockScreenStore.publish(context, projection(sessionId = "session-2", owner = "member-2"))
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-1"))
        val second = WorkoutLockScreenStore.complete(context, "session-2", "token-1")!!
        WorkoutLockScreenStore.acknowledge(context, setOf(first.getString("eventId")))
        val retained = WorkoutLockScreenStore.readEvents(context).single()
        assertEquals(second.getString("eventId"), retained["eventId"])
        assertEquals("member-2", retained["ownerKey"])
        assertEquals(
            WorkoutLockScreenStore.guestOwnerKey(context),
            WorkoutLockScreenStore.guestOwnerKey(context.createPackageContext(context.packageName, 0)),
        )
    }

    @Test
    fun anExpiredProjectionAndAnUnrecordableSetCannotBeCompleted() {
        val state = projection(canComplete = false)
        WorkoutLockScreenStore.publish(context, state)
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-1"))
        assertTrue(WorkoutLockScreenStore.readEvents(context).isEmpty())

        WorkoutLockScreenStore.publish(context, projection())
        // Replace just the stored expiry to represent clock passage without sleeping.
        val prefs = context.getSharedPreferences("setflow_lock_screen_workout", Context.MODE_PRIVATE)
        val json = org.json.JSONObject(prefs.getString("journal_v1", null)!!)
        json.getJSONObject("state").put("expiresAtMillis", System.currentTimeMillis() - 1L)
        prefs.edit().putString("journal_v1", json.toString()).commit()
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-1"))
    }

    @Test
    fun notificationCompletionUsesAServiceAndKeepsAReceiptWithoutOpeningTheApp() {
        WorkoutLockScreenStore.publish(context, projection())
        val controller = Robolectric.buildService(RestTimerService::class.java,
            Intent(context, RestTimerService::class.java)
                .setAction("com.teampara.setflow.action.REFRESH_LOCK_SCREEN_WORKOUT"))
            .create().startCommand(0, 1)
        controllers.add(controller)
        val manager = context.getSystemService(NotificationManager::class.java)
        val notification = shadowOf(manager).getNotification(5101)
        assertNotNull(notification)
        assertEquals(Notification.VISIBILITY_PUBLIC, notification.visibility)
        assertEquals("세트 완료", notification.actions.single().title)
        val action = shadowOf(notification.actions.single().actionIntent).savedIntent
        assertEquals("com.teampara.setflow.action.COMPLETE_LOCK_SCREEN_WORKOUT", action.action)
        controller.get().onStartCommand(action, 0, 2)

        assertEquals(1, WorkoutLockScreenStore.readEvents(context).size)
        assertNull(shadowOf(context as Application).nextStartedActivity)
        assertEquals("벤치 프레스 · 2/2세트",
            shadowOf(manager).getNotification(5101).extras.getString(Notification.EXTRA_TITLE))
    }

    @Test
    fun stoppingRestReturnsToTheNextSetInTheSameForegroundNotification() {
        WorkoutLockScreenStore.publish(context, projection(restSeconds = 90))
        val controller = Robolectric.buildService(RestTimerService::class.java,
            Intent(context, RestTimerService::class.java)
                .setAction("com.teampara.setflow.action.REFRESH_LOCK_SCREEN_WORKOUT"))
            .create().startCommand(0, 1)
        controllers.add(controller)
        val manager = context.getSystemService(NotificationManager::class.java)
        val complete = shadowOf(shadowOf(manager).getNotification(5101)
            .actions.single().actionIntent).savedIntent
        controller.get().onStartCommand(complete, 0, 2)
        val startRest = shadowOf(context as Application).nextStartedService
        assertNotNull(startRest)
        controller.get().onStartCommand(startRest, 0, 3)
        assertTrue(RestTimerService.status(context)["remainingSeconds"] as Int > 0)
        controller.get().onStartCommand(Intent(context, RestTimerService::class.java)
            .setAction("com.teampara.setflow.action.CANCEL_REST_TIMER"), 0, 4)
        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        assertEquals("세트 완료", shadowOf(manager).getNotification(5101).actions.single().title)
        assertFalse(shadowOf(controller.get()).isStoppedBySelf)
        assertEquals(1, WorkoutLockScreenStore.readEvents(context).size)
    }

    @Test
    fun incompleteValuesShowOnlyAnAppEditingAction() {
        WorkoutLockScreenStore.publish(context, projection(canComplete = false))
        val controller = Robolectric.buildService(RestTimerService::class.java,
            Intent(context, RestTimerService::class.java)
                .setAction("com.teampara.setflow.action.REFRESH_LOCK_SCREEN_WORKOUT"))
            .create().startCommand(0, 1)
        controllers.add(controller)
        val manager = context.getSystemService(NotificationManager::class.java)
        assertEquals("앱에서 수정", shadowOf(manager).getNotification(5101).actions.single().title)
        assertTrue(WorkoutLockScreenStore.readEvents(context).isEmpty())
    }

    @Test
    fun aCompletionBetweenDartReadAndPublishCannotBeReplacedByAnOlderPlan() {
        WorkoutLockScreenStore.publish(context, projection())
        assertTrue(WorkoutLockScreenStore.readEvents(context).isEmpty())
        val receipt = WorkoutLockScreenStore.complete(context, "session-1", "token-1")!!
        assertFalse(WorkoutLockScreenStore.publish(context, projection(sessionId = "replacement")))
        assertEquals("session-1", WorkoutLockScreenStore.state(context)!!.getString("sessionId"))
        assertEquals("token-2", WorkoutLockScreenStore.currentSet(context)!!.getString("token"))
        assertEquals(1, WorkoutLockScreenStore.readEvents(context).size)
        WorkoutLockScreenStore.acknowledge(context, setOf(receipt.getString("eventId")))
        assertTrue(WorkoutLockScreenStore.publish(context, projection(sessionId = "replacement")))
        // A deliberate in-app undo can publish the same values with a new generation.
        assertNull(WorkoutLockScreenStore.complete(context, "session-1", "token-1"))
        assertNotNull(WorkoutLockScreenStore.complete(context, "replacement", "token-1"))
    }

    @Test
    fun enablingDuringAnExistingRestRestoresTheDeadlineInsteadOfADeadCompleteButton() {
        val deadline = System.currentTimeMillis() + 90_000L
        WorkoutLockScreenStore.publish(context, projection().plus("restEndsAtMillis" to deadline))
        val controller = Robolectric.buildService(RestTimerService::class.java,
            Intent(context, RestTimerService::class.java)
                .setAction("com.teampara.setflow.action.REFRESH_LOCK_SCREEN_WORKOUT"))
            .create().startCommand(0, 1)
        controllers.add(controller)
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
        val manager = context.getSystemService(NotificationManager::class.java)
        assertEquals(listOf("+30초", "타이머 종료"),
            shadowOf(manager).getNotification(5101).actions.map { it.title.toString() })
        assertTrue(WorkoutLockScreenStore.readEvents(context).isEmpty())
    }

    private fun projection(
        sessionId: String = "session-1",
        owner: String = "member-1",
        restSeconds: Int = 0,
        canComplete: Boolean = true,
    ): Map<String, Any> = mapOf(
        "schemaVersion" to 1,
        "sessionId" to sessionId,
        "ownerKey" to owner,
        "workoutDate" to SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date()),
        "publishedAtMillis" to System.currentTimeMillis() - 1L,
        "expiresAtMillis" to System.currentTimeMillis() + 3_600_000L,
        "restEndsAtMillis" to 0L,
        "unit" to "kg",
        "autoStartRestTimer" to true,
        "showCompletion" to false,
        "vibrate" to false,
        "sound" to false,
        "countdownSeconds" to 0,
        "sets" to (1..2).map { number -> mapOf(
            "token" to "token-$number",
            "fingerprint" to "token-$number",
            "exerciseEntryId" to "entry-bench",
            "templateId" to "bench",
            "exerciseName" to "벤치 프레스",
            "setNumber" to number,
            "setTotal" to 2,
            "measurement" to "weightReps",
            "valuesLabel" to "40kg × 10회",
            "weight" to 40.0,
            "reps" to 10,
            "durationSeconds" to 0,
            "distanceKm" to 0.0,
            "intensityRpe" to 0.0,
            "type" to "일반",
            "restSeconds" to restSeconds,
            "canComplete" to canComplete,
        ) },
    )
}
