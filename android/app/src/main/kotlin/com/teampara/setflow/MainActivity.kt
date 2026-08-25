package com.teampara.setflow

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_PERMISSION_REQUEST,
                        )
                    }
                    RestTimerService.start(
                        this,
                        seconds,
                        call.argument<Boolean>("showCompletionNotification") ?: true,
                        call.argument<Boolean>("vibrate") ?: true,
                        call.argument<Boolean>("sound") ?: true,
                        call.argument<Number>("countdownSeconds")?.toInt() ?: 30,
                    )
                    result.success(null)
                }
                "cancel" -> {
                    RestTimerService.cancel(this)
                    result.success(null)
                }
                "status" -> result.success(RestTimerService.status(this))
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 4312
    }
}
