package com.teampara.setflow

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ContextWrapper
import android.content.Intent
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class RestTimerNotificationSettingsTest {
    private lateinit var context: Application

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
    }

    @Test
    fun notificationStatusRequiresRuntimePermissionAndEnabledSystemNotifications() {
        val manager = context.getSystemService(NotificationManager::class.java)
        shadowOf(manager).setNotificationsEnabled(true)
        shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertTrue(RestTimerService.notificationsAllowed(context))

        shadowOf(context).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertFalse(RestTimerService.notificationsAllowed(context))

        shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        shadowOf(manager).setNotificationsEnabled(false)
        assertFalse(RestTimerService.notificationsAllowed(context))
    }

    @Test
    @Config(sdk = [32])
    fun olderAndroidOnlyNeedsSystemNotificationsEnabled() {
        val manager = context.getSystemService(NotificationManager::class.java)
        shadowOf(context).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        shadowOf(manager).setNotificationsEnabled(true)
        assertTrue(RestTimerService.notificationsAllowed(context))

        shadowOf(manager).setNotificationsEnabled(false)
        assertFalse(RestTimerService.notificationsAllowed(context))
    }

    @Test
    fun explicitSettingsActionOpensThisAppsNotificationSettings() {
        assertTrue(RestTimerService.openNotificationSettings(context))
        val intent = shadowOf(context).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, intent.action)
        assertEquals(context.packageName, intent.getStringExtra(Settings.EXTRA_APP_PACKAGE))
        assertTrue(intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    @Test
    @Config(sdk = [25])
    fun oldAndroidOpensAppDetailsWhereNotificationSettingsAreAvailable() {
        assertTrue(RestTimerService.openNotificationSettings(context))
        val intent = shadowOf(context).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.action)
        assertEquals("package:${context.packageName}", intent.data.toString())
    }

    @Test
    fun unsupportedOrDeniedSettingsLaunchReturnsFalse() {
        for (failure in listOf(ActivityNotFoundException(), SecurityException())) {
            val unavailable = object : ContextWrapper(context) {
                override fun startActivity(intent: Intent) {
                    throw failure
                }
            }
            assertFalse(RestTimerService.openNotificationSettings(unavailable))
        }
    }
}
