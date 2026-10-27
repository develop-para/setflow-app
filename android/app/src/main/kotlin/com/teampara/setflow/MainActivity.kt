package com.teampara.setflow

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        // Persist the user's intent across Activity/process recreation while
        // Android's special-access Settings screen is in front of the app.
        RestTimerService.completeOverlayPermissionRequest(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.teampara.setflow/app_updates",
        ).setMethodCallHandler(FirebaseAppUpdateBridge())
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WorkoutLockScreenBridge.CHANNEL_NAME,
        ).setMethodCallHandler(WorkoutLockScreenBridge(this))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.teampara.setflow/app_background",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Keep the activity and its Flutter engine in the task, just as
                // Home does. The foreground rest timer remains independent.
                "moveToBackground" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RestTimerService.CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val seconds = call.argument<Number>("seconds")?.toInt() ?: 0
                    if (seconds <= 0) {
                        result.error("invalid_seconds", "Timer seconds must be positive.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        RestTimerService.start(
                            this,
                            seconds,
                            call.argument<Boolean>("showCompletionNotification") ?: true,
                            call.argument<Boolean>("vibrate") ?: true,
                            call.argument<Boolean>("sound") ?: true,
                            call.argument<Number>("countdownSeconds")?.toInt() ?: 30,
                            call.argument<String>("detail"),
                            call.argument<String>("workoutDate"),
                            call.argument<String>("sessionId"),
                            call.argument<Number>("endsAtMillis")?.toLong(),
                        )
                        result.success(null)
                    } catch (_: SecurityException) {
                        result.error("rest_timer_unavailable", "Rest timer service permission was denied.", null)
                    } catch (_: IllegalStateException) {
                        result.error("rest_timer_unavailable", "Android prevented the background timer from starting.", null)
                    }
                }
                "cancel" -> {
                    RestTimerService.cancel(this)
                    result.success(null)
                }
                "status" -> result.success(RestTimerService.status(this))
                "notificationStatus" -> result.success(RestTimerService.notificationsAllowed(this))
                "openNotificationSettings" -> result.success(RestTimerService.openNotificationSettings(this))
                "overlayStatus" -> result.success(RestTimerService.overlayStatus(this))
                "setOverlayEnabled" -> {
                    RestTimerService.setOverlayEnabled(
                        this,
                        call.argument<Boolean>("enabled") ?: false,
                    )
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    // This method is called only after an explicit Settings tap.
                    try {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        ))
                        RestTimerService.beginOverlayPermissionRequest(this)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
                "consumePendingWorkoutOpen" ->
                    result.success(RestTimerService.consumePendingWorkoutOpen(this))
                "clearCompletionNotification" -> {
                    RestTimerService.clearCompletion(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

}
