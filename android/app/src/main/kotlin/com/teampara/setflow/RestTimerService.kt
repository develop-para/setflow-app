package com.teampara.setflow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.math.ceil

class RestTimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var finishRunnable: Runnable? = null
    private val beepRunnables = mutableListOf<Runnable>()
    private var toneGenerator: ToneGenerator? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
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
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
        clearBeeps()
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }

    private val preferences
        get() = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    private fun restoreTimer() {
        val endsAt = preferences.getLong(KEY_ENDS_AT, 0L)
        if (!preferences.getBoolean(KEY_ACTIVE, false) || endsAt <= System.currentTimeMillis()) {
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
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
        clearBeeps()
        preferences.edit().clear().apply()
        RestTimerWidgetProvider.updateAll(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun finishTimer() {
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
        val builder = Notification.Builder(this, ONGOING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rest_timer)
            .setContentTitle(getString(R.string.rest_timer_running))
            .setContentText(detail)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setChronometerCountDown(true)
        }
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
        return Notification.Builder(
            this,
            if (vibrate) COMPLETE_CHANNEL_ID else COMPLETE_SILENT_CHANNEL_ID,
        )
            .setSmallIcon(R.drawable.ic_stat_rest_timer)
            .setContentTitle(getString(R.string.rest_timer_complete))
            .setContentText(getString(R.string.rest_timer_complete_message))
            .setContentIntent(openIntent)
            .setAutoCancel(true)
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

    companion object {
        const val CHANNEL_NAME = "com.teampara.setflow/rest_timer"
        const val PREFERENCES_NAME = "setflow_rest_timer"
        const val KEY_ENDS_AT = "ends_at"
        const val KEY_ACTIVE = "active"
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
            if (remaining <= 0 && prefs.getBoolean(KEY_ACTIVE, false)) {
                prefs.edit().putBoolean(KEY_ACTIVE, false).putLong(KEY_ENDS_AT, 0L).apply()
                RestTimerWidgetProvider.updateAll(context)
            }
            return mapOf(
                "remainingSeconds" to remaining,
                "endsAtMillis" to if (remaining > 0) endsAt else 0L,
            )
        }
    }
}
