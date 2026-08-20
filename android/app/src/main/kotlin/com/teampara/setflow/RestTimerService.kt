package com.teampara.setflow

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import kotlin.math.ceil

class RestTimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var finishRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> cancelTimer()
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
                    .apply()
                runTimer(endsAt)
            }
            else -> restoreTimer()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
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
        preferences.edit().clear().apply()
        RestTimerWidgetProvider.updateAll(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun finishTimer() {
        finishRunnable?.let(handler::removeCallbacks)
        finishRunnable = null
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
        val builder = Notification.Builder(this, ONGOING_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rest_timer)
            .setContentTitle(getString(R.string.rest_timer_running))
            .setContentText(getString(R.string.rest_timer_background_message))
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setWhen(endsAt)
            .setUsesChronometer(true)
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
        private const val ACTION_START = "com.teampara.setflow.action.START_REST_TIMER"
        private const val ACTION_CANCEL = "com.teampara.setflow.action.CANCEL_REST_TIMER"
        private const val EXTRA_SECONDS = "seconds"
        private const val EXTRA_SHOW_COMPLETION = "show_completion"
        private const val EXTRA_VIBRATE = "vibrate"
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
        ) {
            val intent = Intent(context, RestTimerService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SECONDS, seconds.coerceIn(1, 3_600))
                .putExtra(EXTRA_SHOW_COMPLETION, showCompletionNotification)
                .putExtra(EXTRA_VIBRATE, vibrate)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
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
