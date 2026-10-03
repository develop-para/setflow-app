package com.teampara.setflow

import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class SetflowApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // FCM can start this process without opening the Flutter activity.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                getString(R.string.push_channel_id),
                getString(R.string.push_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.push_channel_description)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }
}
