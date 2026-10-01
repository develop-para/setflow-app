import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Signing material lives outside version control (android/key.properties is
// gitignored). When it is missing — CI without secrets, a fresh clone — the
// release build falls back to the debug key so `flutter run --release` still
// works locally instead of failing the configuration phase.
val keystoreProperties = Properties().apply {
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) {
        keystoreFile.inputStream().use { load(it) }
    }
}
val hasUploadKeystore = keystoreProperties.getProperty("storeFile") != null

// Flutter와 네이티브가 같은 플래그를 읽는다. 일반/Play 빌드에는 설치 SDK를 넣지 않는다.
val appDistributionUpdates = (project.findProperty("dart-defines") as? String)
    ?.split(",")
    ?.any { String(Base64.getDecoder().decode(it)) == "APP_DISTRIBUTION_UPDATES=true" }
    ?: false

android {
    buildFeatures { buildConfig = true }
    namespace = "com.teampara.setflow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        buildConfigField("boolean", "APP_DISTRIBUTION_UPDATES", appDistributionUpdates.toString())
        applicationId = "com.teampara.setflow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKeystore) {
            create("upload") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKeystore) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.firebase:firebase-appdistribution-api:16.0.0-beta20")
    if (appDistributionUpdates) {
        implementation("com.google.firebase:firebase-appdistribution:16.0.0-beta20")
    }
}
