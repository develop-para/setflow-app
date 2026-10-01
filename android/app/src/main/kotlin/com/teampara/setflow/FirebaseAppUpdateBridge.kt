package com.teampara.setflow

import com.google.firebase.appdistribution.FirebaseAppDistribution
import com.google.firebase.appdistribution.FirebaseAppDistributionException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 배포 SDK를 아는 유일한 업데이트 어댑터. 자동 조회에서는 UI를 열지 않는다. */
class FirebaseAppUpdateBridge : MethodChannel.MethodCallHandler {
    private var busy = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!BuildConfig.APP_DISTRIBUTION_UPDATES) {
            result.error("NOT_IMPLEMENTED", "Updates are disabled in this build.", null)
            return
        }
        if (call.method != "check" && call.method != "install") {
            result.notImplemented()
            return
        }
        if (busy) {
            result.error("BUSY", "An update operation is already in progress.", null)
            return
        }
        busy = true
        try {
            val sdk = FirebaseAppDistribution.getInstance()
            when (call.method) {
                "check" -> {
                    if (sdk.isTesterSignedIn) {
                        check(sdk, result)
                    } else if (call.argument<Boolean>("requestSignIn") == true) {
                        sdk.signInTester()
                            .addOnSuccessListener { check(sdk, result) }
                            .addOnFailureListener { fail(result, it) }
                    } else {
                        busy = false
                        result.success(mapOf("needsSignIn" to true))
                    }
                }
                "install" -> {
                    // SDK가 다운로드 진행 알림과 설치 확인 화면을 담당한다.
                    sdk.updateIfNewReleaseAvailable()
                        .addOnSuccessListener {
                            busy = false
                            result.success(null)
                        }
                        .addOnFailureListener { fail(result, it) }
                }
            }
        } catch (exception: Exception) {
            fail(result, exception)
        }
    }

    private fun check(sdk: FirebaseAppDistribution, result: MethodChannel.Result) {
        sdk.checkForNewRelease()
            .addOnSuccessListener { release ->
                busy = false
                result.success(if (release == null) mapOf("needsSignIn" to false) else mapOf(
                    "needsSignIn" to false,
                    "version" to release.displayVersion,
                    "build" to release.versionCode,
                    "notes" to release.releaseNotes,
                ))
            }
            .addOnFailureListener { fail(result, it) }
    }

    private fun fail(result: MethodChannel.Result, exception: Exception) {
        busy = false
        val code = (exception as? FirebaseAppDistributionException)?.errorCode?.name ?: "UNKNOWN"
        result.error(code, "App update operation failed.", null)
    }
}
