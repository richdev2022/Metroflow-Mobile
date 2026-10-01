plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Services plugin (FCM push): applied ONLY when google-services.json is
// present so CI/local builds keep working before the Firebase config lands.
// Drop google-services.json into android/app/ (package name must equal the
// applicationId below) and this activates automatically.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.Metricorex_flutter"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Core library desugaring is REQUIRED by flutter_local_notifications
        // (java.time APIs on older Android). Enabled for all build types.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.Metricorex_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Matches the requirement of flutter_local_notifications (see
    // https://pub.dev/packages/flutter_local_notifications#4-android-setup)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Facebook-style launcher badge (unread count on the app icon).
    implementation("me.leolin:ShortcutBadger:1.1.22@aar")
}

flutter {
    source = "../.."
}
