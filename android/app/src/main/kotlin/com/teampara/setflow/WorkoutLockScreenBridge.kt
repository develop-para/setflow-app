package com.teampara.setflow

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WorkoutLockScreenBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> {
                    val state = WorkoutLockScreenStore.state(context)
                    result.success(mapOf(
                        "supported" to true,
                        "enabled" to (state != null),
                        "notificationsAllowed" to RestTimerService.notificationsAllowed(context),
                        "ownerKey" to state?.optString("ownerKey"),
                        "workoutDate" to state?.optString("workoutDate"),
                        "sessionId" to state?.optString("sessionId"),
                        "restEndsAtMillis" to WorkoutLockScreenStore.restEndsAt(context),
                    ))
                }
                "openSettings" -> result.success(RestTimerService.openNotificationSettings(context))
                "getGuestOwnerKey" -> result.success(WorkoutLockScreenStore.guestOwnerKey(context))
                "publish" -> {
                    if (!RestTimerService.notificationsAllowed(context)) {
                        result.success(false)
                        return
                    }
                    val payload = call.arguments as? Map<*, *>
                        ?: throw IllegalArgumentException("Missing workout projection")
                    val published = WorkoutLockScreenStore.publish(context, payload)
                    if (published) RestTimerService.refreshWorkout(context)
                    result.success(published)
                }
                "readEvents" -> result.success(WorkoutLockScreenStore.readEvents(context))
                "ack" -> {
                    val eventIds = call.argument<List<String>>("eventIds") ?: emptyList()
                    WorkoutLockScreenStore.acknowledge(context, eventIds.toSet())
                    result.success(null)
                }
                "clear" -> {
                    WorkoutLockScreenStore.clear(context)
                    RestTimerService.refreshWorkout(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("workout_lock_screen_unavailable", error.message, null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.teampara.setflow/lock_screen_workout"
    }
}
