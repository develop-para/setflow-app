package com.teampara.setflow

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Looper
import android.view.WindowManager
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowPowerManager
import org.robolectric.shadows.ShadowSettings
import org.robolectric.shadows.ShadowSystemClock
import org.robolectric.shadows.ShadowWindowManagerImpl
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@LooperMode(LooperMode.Mode.PAUSED)
class RestTimerServiceTest {
    private lateinit var context: Context
    private val controllers = mutableListOf<ServiceController<RestTimerService>>()

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        RestTimerService.onAppVisibilityChanged(true)
        ShadowSettings.setCanDrawOverlays(false)
    }

    @After
    fun tearDown() {
        controllers.forEach { it.destroy() }
        controllers.clear()
        RestTimerService.onAppVisibilityChanged(false)
    }

    @Test
    fun queuedStartKeepsFlutterDeadlineAndExtensionRenewsBoundedWakeLock() {
        val deadline = System.currentTimeMillis() + 90_000L
        val service = startTimer(seconds = 120, endsAt = deadline)
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
        val firstLock = ShadowPowerManager.getLatestWakeLock()
        assertNotNull(firstLock)
        assertTrue(firstLock.isHeld)

        service.onStartCommand(action("EXTEND"), 0, 2)

        assertEquals(deadline + 30_000L, RestTimerService.status(context)["endsAtMillis"])
        assertFalse(firstLock.isHeld)
        val extendedLock = ShadowPowerManager.getLatestWakeLock()
        assertTrue(extendedLock.isHeld)
        service.onStartCommand(action("CANCEL"), 0, 3)
        assertFalse(extendedLock.isHeld)
        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
    }

    @Test
    fun screenOffCompletionReleasesWakeLockAndSilentSoundStillAllowsVibration() {
        startTimer(seconds = 1, sound = false, vibrate = true)
        val lock = ShadowPowerManager.getLatestWakeLock()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))

        assertFalse(lock.isHeld)
        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        val manager = context.getSystemService(NotificationManager::class.java)
        val notification = shadowOf(manager).getNotification(5102)
        assertNotNull(notification)
        val channel = manager.getNotificationChannel(notification.channelId)
        assertTrue(channel.shouldVibrate())
        assertNull(channel.sound)
    }

    @Test
    fun completionKeepsAudioResourcesAliveUntilFinishToneEnds() {
        val service = startTimer(seconds = 1, sound = true)
        val lock = ShadowPowerManager.getLatestWakeLock()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertFalse(shadowOf(service).isStoppedBySelf)
        assertTrue(lock.isHeld)

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500))
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertFalse(lock.isHeld)
    }

    @Test
    fun cancelledTimerWithoutLiveServiceNeverStartsABackgroundService() {
        context.getSharedPreferences(RestTimerService.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(RestTimerService.KEY_ACTIVE, true)
            .putLong(RestTimerService.KEY_ENDS_AT, System.currentTimeMillis() + 90_000L)
            .apply()

        RestTimerService.cancel(context)

        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        assertNull(shadowOf(context as Application).nextStartedService)
        assertNotNull(shadowOf(context as Application).nextStoppedService)
    }

    @Test
    fun queuedStartCannotReviveTimerCancelledBeforeServiceCreation() {
        RestTimerService.start(context, 90, true, false, sound = false)
        val queued = shadowOf(context as Application).nextStartedService
        assertNotNull(queued)
        RestTimerService.cancel(context)

        val controller = Robolectric.buildService(RestTimerService::class.java, queued)
            .create().startCommand(0, 1)
        controllers.add(controller)

        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        assertTrue(shadowOf(controller.get()).isStoppedBySelf)
        assertNull(ShadowPowerManager.getLatestWakeLock())
    }

    @Test
    fun staleStartCannotReplaceANewerRunningRest() {
        RestTimerService.start(context, 90, true, false, sound = false)
        val older = shadowOf(context as Application).nextStartedService
        val deadline = System.currentTimeMillis() + 120_000L
        RestTimerService.start(context, 120, true, false, sound = false, endsAtMillis = deadline)
        val newer = shadowOf(context as Application).nextStartedService
        val controller = Robolectric.buildService(RestTimerService::class.java, newer)
            .create().startCommand(0, 2)
        controllers.add(controller)

        controller.get().onStartCommand(older, 0, 1)

        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
        assertFalse(shadowOf(controller.get()).isStoppedBySelf)
        assertTrue(ShadowPowerManager.getLatestWakeLock().isHeld)
    }

    @Test
    fun returningAfterSuspendedCallbacksFinishesExpiredTimerImmediately() {
        startTimer(seconds = 10, sound = false)
        val lock = ShadowPowerManager.getLatestWakeLock()
        // Represent a wall-clock deadline passed while the Handler was suspended;
        // Robolectric's uptime clock does not advance System.currentTimeMillis().
        context.getSharedPreferences(RestTimerService.PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putLong(RestTimerService.KEY_ENDS_AT, System.currentTimeMillis() - 1L).apply()

        RestTimerService.onAppVisibilityChanged(true)

        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        assertFalse(lock.isHeld)
        val manager = context.getSystemService(NotificationManager::class.java)
        assertNotNull(shadowOf(manager).getNotification(5102))
    }

    @Test
    fun vendorSuspendedCpuDoesNotReplayTheRestAfterWaking() {
        val service = startTimer(seconds = 10, sound = false)
        // Simulate an OEM ignoring the partial wake lock during deep idle:
        // elapsed time advances, but Handler uptime remains suspended.
        ShadowSystemClock.simulateDeepSleep(Duration.ofSeconds(11))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))

        assertEquals(0, RestTimerService.status(context)["remainingSeconds"])
        assertTrue(shadowOf(service).isStoppedBySelf)
        assertFalse(ShadowPowerManager.getLatestWakeLock().isHeld)
    }

    @Test
    fun serviceDestructionReleasesCpuWithoutLosingRestorableDeadline() {
        val deadline = System.currentTimeMillis() + 90_000L
        startTimer(seconds = 90, endsAt = deadline)
        val oldLock = ShadowPowerManager.getLatestWakeLock()
        controllers.removeAt(0).destroy()
        assertFalse(oldLock.isHeld)
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])

        val restored = Robolectric.buildService(RestTimerService::class.java)
            .create().startCommand(0, 2)
        controllers.add(restored)
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
        assertTrue(ShadowPowerManager.getLatestWakeLock().isHeld)
    }

    @Test
    fun permissionIntentSurvivesRecreationAndDenialIsConsumedOnce() {
        RestTimerService.beginOverlayPermissionRequest(context)
        ShadowSettings.setCanDrawOverlays(true)
        RestTimerService.completeOverlayPermissionRequest(context)
        assertEquals(true, RestTimerService.overlayStatus(context)["enabled"])

        RestTimerService.setOverlayEnabled(context, false)
        RestTimerService.beginOverlayPermissionRequest(context)
        ShadowSettings.setCanDrawOverlays(false)
        RestTimerService.completeOverlayPermissionRequest(context)
        ShadowSettings.setCanDrawOverlays(true)
        RestTimerService.completeOverlayPermissionRequest(context)
        assertEquals(false, RestTimerService.overlayStatus(context)["enabled"])
    }

    @Test
    fun floatingCountdownAppearsOverOtherAppsAndHidesWhenWorkoutReturns() {
        ShadowSettings.setCanDrawOverlays(true)
        RestTimerService.setOverlayEnabled(context, true)
        startTimer(seconds = 90)
        val deadline = RestTimerService.status(context)["endsAtMillis"]
        val windows = Shadow.extract<ShadowWindowManagerImpl>(
            context.getSystemService(WindowManager::class.java),
        )
        assertTrue(windows.views.isEmpty())

        RestTimerService.onAppVisibilityChanged(false)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, windows.views.size)

        RestTimerService.onAppVisibilityChanged(true)
        assertTrue(windows.views.isEmpty())
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
    }

    @Test
    fun revokingFloatingWindowPermissionKeepsRestAndAudioServiceRunning() {
        ShadowSettings.setCanDrawOverlays(true)
        RestTimerService.setOverlayEnabled(context, true)
        val service = startTimer(seconds = 90)
        val deadline = RestTimerService.status(context)["endsAtMillis"]
        RestTimerService.onAppVisibilityChanged(false)
        val windows = Shadow.extract<ShadowWindowManagerImpl>(
            context.getSystemService(WindowManager::class.java),
        )
        assertEquals(1, windows.views.size)

        ShadowSettings.setCanDrawOverlays(false)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(250))

        assertTrue(windows.views.isEmpty())
        assertFalse(shadowOf(service).isStoppedBySelf)
        assertTrue(ShadowPowerManager.getLatestWakeLock().isHeld)
        assertEquals(deadline, RestTimerService.status(context)["endsAtMillis"])
    }

    private fun startTimer(
        seconds: Int,
        endsAt: Long? = null,
        sound: Boolean = false,
        vibrate: Boolean = false,
    ): RestTimerService {
        val intent = action("START")
            .putExtra("seconds", seconds)
            .putExtra("sound", sound)
            .putExtra("vibrate", vibrate)
            .apply { endsAt?.let { putExtra("endsAtMillis", it) } }
        val controller = Robolectric.buildService(RestTimerService::class.java, intent)
            .create().startCommand(0, 1)
        controllers.add(controller)
        return controller.get()
    }

    private fun action(name: String) = Intent(context, RestTimerService::class.java)
        .setAction("com.teampara.setflow.action.${name}_REST_TIMER")
}
