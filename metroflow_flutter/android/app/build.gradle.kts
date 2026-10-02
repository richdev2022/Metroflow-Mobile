plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — fully environment-driven so the SAME keystore is used on
// CI and locally. When ANDROID_KEYSTORE_PATH points at a keystore (set by the
// flutter-build workflow from the ANDROID_KEYSTORE_BASE64 secret), release
// builds are signed with the pinned Metricorex release key. Without it (local
// `flutter run --release`, or CI before the secrets are configured) the build
// falls back to the debug keystore so nothing breaks — but remember: Google
// Sign-In only works in artifacts signed with a keystore whose SHA-1 is
// registered in the Firebase project (see docs/GOOGLE_SSO_ANDROID_SETUP.md).
val envKeystorePath: String? = System.getenv("ANDROID_KEYSTORE_PATH")
val envKeystorePassword: String? = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val envKeyAlias: String? = System.getenv("ANDROID_KEY_ALIAS")
val envKeyPassword: String? = System.getenv("ANDROID_KEY_PASSWORD")

// Google Services plugin (FCM push): applied ONLY when google-services.json is
// present so CI/local builds keep working before the Firebase config lands.
// Drop google-services.json into android/app/ (package name must equal the
// applicationId below) and this activates automatically.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    // Matches the iOS bundle ID and the package registered in the Google /
    // Firebase console for Google SSO + FCM (google-services.json).
    namespace = "com.metricorex.app"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    signingConfigs {
        create("release") {
            if (envKeystorePath != null && envKeystorePassword != null &&
                file(envKeystorePath).exists()
            ) {
                storeFile = file(envKeystorePath)
                storePassword = envKeystorePassword
                keyAlias = envKeyAlias ?: "metricorex"
                keyPassword = envKeyPassword ?: envKeystorePassword
            }
        }
    }

    compileOptions {
        // Core library desugaring is REQUIRED by flutter_local_notifications
        // (java.time APIs on older Android). Enabled for all build types.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.metricorex.app"
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
            // Pinned release keystore when provided via env (CI); debug
            // keystore fallback keeps local --release builds working.
            signingConfig =
                if (signingConfigs.getByName("release").storeFile != null)
                    signingConfigs.getByName("release")
                else
                    signingConfigs.getByName("debug")
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
