import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Local, uncommitted configuration.
 *
 * `local.properties` holds the Maps SDK key and, optionally, release signing
 * details. It is gitignored by the Flutter template, which is exactly why
 * secrets belong here rather than in the manifest or this file.
 */
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}

/**
 * Release signing, read from key.properties if present.
 *
 * Absent (the normal case for a developer checkout) the release build falls
 * back to the debug keystore so `flutter build apk --release` still works for
 * testing. A Play Store upload needs the real thing - see README.
 */
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        FileInputStream(file).use { load(it) }
    }
}

val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.yourtaxi.customer_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // Required by flutter_local_notifications, which uses java.time APIs
        // that only exist natively from API 26. Without this the build fails
        // with "Dependency ':flutter_local_notifications' requires core
        // library desugaring to be enabled for :app."
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.yourtaxi.customer_app"

        // google_maps_flutter and firebase_messaging both require 21+; the
        // secure-storage plugin's EncryptedSharedPreferences needs 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Substituted into AndroidManifest.xml. Empty when unset, which leaves
        // the map blank but keeps the build working.
        manifestPlaceholders["MAPS_API_KEY"] =
            localProperties.getProperty("MAPS_API_KEY") ?: ""
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Lets `--release` be built and tested without a keystore.
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }

        debug {
            // So a debug and a release build can sit on one device at once.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    // Keeps the release APK from shipping every language's resources.
    androidResources {
        localeFilters += listOf("en")
    }
}

dependencies {
    // Backports the java.time APIs flutter_local_notifications needs, so the
    // app still runs on devices below API 26. Must be 2.0.4 or newer for AGP 8.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
