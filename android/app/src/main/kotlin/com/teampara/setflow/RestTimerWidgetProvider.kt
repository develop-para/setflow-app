package com.teampara.setflow

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

class RestTimerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views(context)) }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, RestTimerWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(
                RestTimerService.PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val endsAt = prefs.getLong(RestTimerService.KEY_ENDS_AT, 0L)
            val remainingMillis = endsAt - System.currentTimeMillis()
            val active = prefs.getBoolean(RestTimerService.KEY_ACTIVE, false) &&
                remainingMillis > 0
            val openIntent = PendingIntent.getActivity(
                context,
                10,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return RemoteViews(context.packageName, R.layout.rest_timer_widget).apply {
                setOnClickPendingIntent(R.id.rest_timer_widget_root, openIntent)
                setViewVisibility(
                    R.id.rest_timer_widget_chronometer,
                    if (active) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.rest_timer_widget_ready,
                    if (active) View.GONE else View.VISIBLE,
                )
                setTextViewText(
                    R.id.rest_timer_widget_status,
                    context.getString(
                        if (active) R.string.rest_timer_widget_status_running
                        else R.string.rest_timer_widget_status_ready,
                    ),
                )
                if (active) {
                    val base = SystemClock.elapsedRealtime() + remainingMillis
                    setChronometer(R.id.rest_timer_widget_chronometer, base, null, true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        setChronometerCountDown(R.id.rest_timer_widget_chronometer, true)
                    }
                }
            }
        }
    }
}
