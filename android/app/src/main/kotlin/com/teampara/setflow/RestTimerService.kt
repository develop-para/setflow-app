package com.teampara.setflow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Vibrator
import android.provider.Settings
import java.lang.ref.WeakReference
import kotlin.math.ceil

class RestTimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var finishRunnable: Runnable? = null
    private val beepRunnables = mutableListOf<Runnable>()
    private var toneGenerator: ToneGenerator? = null
    private lateinit var overlay: RestTimerOverlay

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        liveService = WeakReference(this)
        overlay = RestTimerOverlay(this, ::cancelTimer, ::openWorkout)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> cancelTimer()
            ACTION_EXTEND -> extendTimer()
            ACTION_START -> {
                val seconds = intent.getIntExtra(EXTRA_SECONDS, 0)
                if (seconds <= 0) {
                    cancelTimer()
                    return START_NOT_STICKY
                }
                val endsAt = System.currentTimeMillis() + seconds * 1_000L
                preferences.edit()
                    .putLong(KEY_ENDS_AT, endsAt)
                    .putBoolean(KEY_ACTIVE, true)
                    .putBoolean(
                        KEY_SHOW_COMPLETION,
                        intent.getBooleanExtra(EXTRA_SHOW_COMPLETION, true),
                    )
                    .putBoolean(KEY_VIBRATE, intent.getBooleanExtra(EXTRA_VIBRATE, true))
                    .putBoolean(KEY_SOUND, intent.getBooleanExtra(EXTRA_SOUND, true))
                    .putInt(
                        KEY_COUNTDOWN_SECONDS,
                        intent.getIntExtra(EXTRA_COUNTDOWN_SECONDS, 30).coerceIn(0, 120),
                    )
                    .putString(KEY_DETAIL, intent.getStringExtra(EXTRA_DETAIL))
                    .putString(KEY_WORKOUT_DATE, intent.getStringExtra(EXTRA_WORKOUT_DATE))
                    .putString(KEY_SESSION_ID, intent.getStringExtra(EXTRA_SESSION_ID))
                    .apply()
                runTimer(endsAt)
            }
            else -> restoreTimer()
        }
        return START_STICKY
    }

    // The "+30s" action on the notification. Dart learns the new end time on
    // resume (syncRestTimerFromPlatform) -- closing the shade resumes the app,
    // and the service already owns the truth about when rest ends.
    private fun extendTimer() {
        if (!preferences.getBoolean(KEY_ACTIVE, false)) return
        val now = System.currentTimeMillis()
        val endsAt = maxOf(preferences.getLong(KEY_ENDS_AT, now), now) + EXTEND_MILLIS
        preferences.edit().putLong(KEY_ENDS_AT, endsAt).apply()
        runTimer(endsAt)
    }

    override fun onDestroy() {
        overlay.hide()
        if (liveService?.get() === this) liveService = null
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
        clearBeeps()
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Reinflate text at the new font scale and clamp to the rotated display.
        overlay.hide()
        refreshOverlayVisibility()
    }

    private val preferences
        get() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private fun restoreTimer() {
        val endsAt = preferences.getLong(KEY_ENDS_AT, 0L)
        if (!preferences.getBoolean(KEY_ACTIVE, false)) {
            cancelTimer()
            return
        }
        if (endsAt <= System.currentTimeMillis()) {
            finishTimer()
            return
        }
        runTimer(endsAt)
    }

    private fun runTimer(endsAt: Long) {
        finishRunnable?.let(handler::removeCallbacks)
        startTimerForeground(buildOngoingNotification(endsAt))
        RestTimerWidgetProvider.updateAll(this)
        val remaining = (endsAt - System.currentTimeMillis()).coerceAtLeast(1L)
        finishRunnable = Runnable(::finishTimer).also {
            handler.postDelayed(it, remaining)
        }
        scheduleBeeps(endsAt)
        refreshOverlayVisibility()
    }

    private fun refreshOverlayVisibility() {
        val endsAt = preferences.getLong(KEY_ENDS_AT, 0L)
        if (!appInForeground && preferences.getBoolean(KEY_ACTIVE, false) &&
            endsAt > System.currentTimeMillis() &&
            overlayPreferences(this).getBoolean(KEY_OVERLAY_ENABLED, false) &&
            Settings.canDrawOverlays(this)
        ) {
            val detail = preferences.getString(KEY_DETAIL, null)
                ?.takeIf { it.isNotBlank() }
                ?: getString(R.string.rest_timer_background_message)
            try {
                overlay.show(endsAt, detail)
            } catch (_: RuntimeException) {
                // A floating window is optional; timer/audio keep running even
                // if a vendor display implementation rejects its window context.
                overlay.hide()
            }
        } else {
            overlay.hide()
        }
    }

    private fun openWorkout() {
        val pending = overlayPreferences(this)
        pending.edit()
            .putBoolean(KEY_PENDING_WORKOUT_OPEN, true)
            .putString(KEY_WORKOUT_DATE, preferences.getString(KEY_WORKOUT_DATE, null))
            .putString(KEY_SESSION_ID, preferences.getString(KEY_SESSION_ID, null))
            .apply()
        try {
            // A direct user tap on the visible overlay opens the existing task.
            // Keep that window attached until Android has accepted the launch.
            startActivity(Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
            overlay.hide()
        } catch (_: RuntimeException) {
            // Keep the timer controls available if this device rejects the launch.
            pending.edit().remove(KEY_PENDING_WORKOUT_OPEN).apply()
        }
    }

    // Lets the lifter hear the rest ending without watching the screen: one
    // alert tone when the configured countdown begins, a short tick on each of
    // the last three seconds, and a longer tone at zero (in finishTimer).
    private fun scheduleBeeps(endsAt: Long) {
        clearBeeps()
        if (!preferences.getBoolean(KEY_SOUND, true)) return
        val now = System.currentTimeMillis()
        val countdown = preferences.getInt(KEY_COUNTDOWN_SECONDS, 30)
        if (countdown > 0) {
            val alertAt = endsAt - countdown * 1_000L
            if (alertAt > now) {
                postBeep(alertAt - now) { playTone(ToneGenerator.TONE_PROP_BEEP2, 220) }
            }
        }
        for (second in 3 downTo 1) {
            val tickAt = endsAt - second * 1_000L
            if (tickAt > now) {
                postBeep(tickAt - now) { playTone(ToneGenerator.TONE_PROP_BEEP, 140) }
            }
        }
    }

    private fun postBeep(delayMillis: Long, action: () -> Unit) {
        val runnable = Runnable(action)
        beepRunnables.add(runnable)
        handler.postDelayed(runnable, delayMillis)
    }

    private fun clearBeeps() {
        beepRunnables.forEach(handler::removeCallbacks)
        beepRunnables.clear()
    }

    private fun playTone(tone: Int, durationMillis: Int) {
        val generator = toneGenerator ?: try {
            ToneGenerator(AudioManager.STREAM_MUSIC, 80).also { toneGenerator = it }
        } catch (_: RuntimeException) {
            // No audio resources: stay silent. The timer matters more than the beep.
            return
        }
        generator.startTone(tone, durationMillis)
    }

    private fun startTimerForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun cancelTimer() {
        overlay.hide()
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
        clearBeeps()
        toneGenerator?.stopTone()
        getSystemService(Vibrator::class.java)?.cancel()
        clearCompletion(this)
        preferences.edit().clear().apply()
        RestTimerWidgetProvider.updateAll(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun finishTimer() {
        overlay.hide()
        if (!preferences.getBoolean(KEY_ACTIVE, false)) return
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
        clearBeeps()
        if (preferences.getBoolean(KEY_SOUND, true)) {
            playTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 500)
        }
        val showCompletion = preferences.getBoolean(KEY_SHOW_COMPLETION, true)
        val vibrate = preferences.getBoolean(KEY_VIBRATE, true)
        preferences.edit()
            .putBoolean(KEY_ACTIVE, false)
            .putLong(KEY_ENDS_AT, 0L)
            .apply()
        RestTimerWidgetProvider.updateAll(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (showCompletion) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(COMPLETION_NOTIFICATION_ID, buildCompletionNotification(vibrate))
        }
        stopSelf()
    }

    private fun buildOngoingNotification(endsAt: Long): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, RestTimerService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val extendIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, RestTimerService::class.java).setAction(ACTION_EXTEND),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Second line says where the lifter is ("next: squat"), the same
        // answer the in-app rest screen gives. Falls back to the generic copy
        // when the timer was started without that context.
        val detail = preferences.getString(KEY_DETAIL, null)
            ?.takeIf { it.isNotBlank() }
            ?: getString(R.string.rest_timer_background_message)
        val builder = notificationBuilder(ONGOING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rest_timer)
            .setContentTitle(getString(R.string.rest_timer_running))
            .setContentText(detail)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Notification.CATEGORY_STOPWATCH
                else Notification.CATEGORY_PROGRESS,
            )
            .setWhen(endsAt)
            .setUsesChronometer(true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.rest_timer_extend),
                    extendIntent,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.rest_timer_stop),
                    stopIntent,
                ).build(),
            )
        builder.setChronometerCountDown(true)
        return builder.build()
    }

    private fun buildCompletionNotification(vibrate: Boolean): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            2,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return notificationBuilder(
            if (vibrate) COMPLETE_CHANNEL_ID else COMPLETE_SILENT_CHANNEL_ID,
        )
            .setSmallIcon(R.drawable.ic_stat_rest_timer)
            .setContentTitle(getString(R.string.rest_timer_complete))
            .setContentText(getString(R.string.rest_timer_complete_message))
            .setContentIntent(openIntent)
            .setAutoCancel(true)
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O && vibrate) {
                    setDefaults(Notification.DEFAULT_VIBRATE)
                }
            }
            .setCategory(Notification.CATEGORY_ALARM)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                ONGOING_CHANNEL_ID,
                getString(R.string.rest_timer_channel_running),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.rest_timer_channel_running_description)
                setSound(null, null)
                enableVibration(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                COMPLETE_CHANNEL_ID,
                getString(R.string.rest_timer_channel_complete),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.rest_timer_channel_complete_description)
                enableVibration(true)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                COMPLETE_SILENT_CHANNEL_ID,
                getString(R.string.rest_timer_channel_complete_silent),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = getString(R.string.rest_timer_channel_complete_description)
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    @Suppress("DEPRECATION")
    private fun notificationBuilder(channelId: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.teampara.setflow/rest_timer"
        const val PREFERENCES_NAME = "setflow_rest_timer"
        const val KEY_ENDS_AT = "ends_at"
        const val KEY_ACTIVE = "active"
        private const val KEY_WORKOUT_DATE = "workout_date"
        private const val KEY_SESSION_ID = "session_id"
        private const val OVERLAY_PREFERENCES_NAME = "setflow_rest_timer_overlay"
        private const val KEY_OVERLAY_ENABLED = "enabled"
        private const val KEY_PENDING_WORKOUT_OPEN = "pending_workout_open"
        private var appInForeground = false
        private var liveService: WeakReference<RestTimerService>? = null
        private const val KEY_SHOW_COMPLETION = "show_completion"
        private const val KEY_VIBRATE = "vibrate"
        private const val KEY_SOUND = "sound"
        private const val KEY_COUNTDOWN_SECONDS = "countdown_seconds"
        private const val KEY_DETAIL = "detail"
        private const val ACTION_START = "com.teampara.setflow.action.START_REST_TIMER"
        private const val ACTION_CANCEL = "com.teampara.setflow.action.CANCEL_REST_TIMER"
        private const val ACTION_EXTEND = "com.teampara.setflow.action.EXTEND_REST_TIMER"
        private const val EXTEND_MILLIS = 30_000L
        private const val EXTRA_DETAIL = "detail"
        private const val EXTRA_WORKOUT_DATE = "workoutDate"
        private const val EXTRA_SESSION_ID = "sessionId"
        private const val EXTRA_SECONDS = "seconds"
        private const val EXTRA_SHOW_COMPLETION = "show_completion"
        private const val EXTRA_VIBRATE = "vibrate"
        private const val EXTRA_SOUND = "sound"
        private const val EXTRA_COUNTDOWN_SECONDS = "countdown_seconds"
        private const val ONGOING_CHANNEL_ID = "rest_timer_running"
        private const val COMPLETE_CHANNEL_ID = "rest_timer_complete"
        private const val COMPLETE_SILENT_CHANNEL_ID = "rest_timer_complete_silent"
        private const val NOTIFICATION_ID = 5101
        private const val COMPLETION_NOTIFICATION_ID = 5102

        fun start(
            context: Context,
            seconds: Int,
            showCompletionNotification: Boolean,
            vibrate: Boolean,
            sound: Boolean = true,
            countdownSeconds: Int = 30,
            detail: String? = null,
            workoutDate: String? = null,
            sessionId: String? = null,
        ) {
            // 새 휴식이 시작됐으면 지난 휴식의 "끝났어요"는 지나간 말이다.
            clearCompletion(context)
            val intent = Intent(context, RestTimerService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SECONDS, seconds.coerceIn(1, 3_600))
                .putExtra(EXTRA_SHOW_COMPLETION, showCompletionNotification)
                .putExtra(EXTRA_VIBRATE, vibrate)
                .putExtra(EXTRA_SOUND, sound)
                .putExtra(EXTRA_COUNTDOWN_SECONDS, countdownSeconds.coerceIn(0, 120))
                .putExtra(EXTRA_DETAIL, detail)
                .putExtra(EXTRA_WORKOUT_DATE, workoutDate)
                .putExtra(EXTRA_SESSION_ID, sessionId)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /// 휴식 끝 알림을 걷어낸다.
        ///
        /// 이 알림은 setAutoCancel(true)라 **탭해야만** 사라진다. 앱을 보면서
        /// 쉰 사람은 탭할 일이 없어서, 알림창에 그것만 남고 런처 아이콘에는
        /// 배지가 계속 붙어 있었다(실기기 보고: "알림 표기가 있는 것 같은데
        /// 들어가면 무슨 알림인지 모르겠네"). 앱을 열었거나 다음 휴식을
        /// 시작했다면 그 알림은 이미 할 일을 마친 것이다.
        fun clearCompletion(context: Context) {
            context.getSystemService(NotificationManager::class.java)
                ?.cancel(COMPLETION_NOTIFICATION_ID)
        }

        fun cancel(context: Context) {
            liveService?.get()?.let {
                it.cancelTimer()
                return
            }
            clearCompletion(context)
            val prefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            if (!prefs.getBoolean(KEY_ACTIVE, false)) {
                prefs.edit().clear().apply()
                RestTimerWidgetProvider.updateAll(context)
                return
            }
            context.startService(
                Intent(context, RestTimerService::class.java).setAction(ACTION_CANCEL),
            )
        }

        fun status(context: Context): Map<String, Any> {
            val prefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            val endsAt = prefs.getLong(KEY_ENDS_AT, 0L)
            val remaining = if (prefs.getBoolean(KEY_ACTIVE, false)) {
                ceil((endsAt - System.currentTimeMillis()).coerceAtLeast(0L) / 1_000.0).toInt()
            } else {
                0
            }
            // Only the timer service finishes a timer. A simultaneous status read
            // must not consume its completion alert or revive a cancelled timer.
            return mapOf(
                "remainingSeconds" to remaining,
                "endsAtMillis" to if (remaining > 0) endsAt else 0L,
            )
        }

        fun onAppVisibilityChanged(inForeground: Boolean) {
            appInForeground = inForeground
            liveService?.get()?.refreshOverlayVisibility()
        }

        fun overlayStatus(context: Context): Map<String, Boolean> = mapOf(
            "enabled" to overlayPreferences(context).getBoolean(KEY_OVERLAY_ENABLED, false),
            "permissionGranted" to Settings.canDrawOverlays(context),
        )

        fun setOverlayEnabled(context: Context, enabled: Boolean) {
            overlayPreferences(context).edit().putBoolean(KEY_OVERLAY_ENABLED, enabled).apply()
            liveService?.get()?.refreshOverlayVisibility()
        }

        fun consumePendingWorkoutOpen(context: Context): Map<String, String?>? {
            val pending = overlayPreferences(context)
            if (!pending.getBoolean(KEY_PENDING_WORKOUT_OPEN, false)) return null
            val payload = mapOf(
                "workoutDate" to pending.getString(KEY_WORKOUT_DATE, null),
                "sessionId" to pending.getString(KEY_SESSION_ID, null),
            )
            pending.edit()
                .remove(KEY_PENDING_WORKOUT_OPEN)
                .remove(KEY_WORKOUT_DATE)
                .remove(KEY_SESSION_ID)
                .apply()
            return payload
        }

        private fun overlayPreferences(context: Context) =
            context.getSharedPreferences(OVERLAY_PREFERENCES_NAME, Context.MODE_PRIVATE)
    }
}
