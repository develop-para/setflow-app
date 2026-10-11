pluginManagement {
    val flutterSdkPath =
        run {
            val localPropertiesFile = file("local.properties")
            val properties = java.util.Properties()
            localPropertiesFile.inputStream().use { properties.load(it) }
            // Flutter가 다시 만든 Windows 경로도 lint 전에 올바른 properties 표기로 저장한다.
            val unescapedDrive = Regex("""(?m)^(?:sdk\.dir|flutter\.sdk)\s*=\s*[A-Za-z]:""")
            if (unescapedDrive.containsMatchIn(localPropertiesFile.readText())) {
                localPropertiesFile.outputStream().use { properties.store(it, null) }
            }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // 푸시 알림용. google-services.json을 읽어 FCM 발신자 ID를 앱에 넣는다.
    id("com.google.gms.google-services") version "4.4.4" apply false
}

include(":app")
