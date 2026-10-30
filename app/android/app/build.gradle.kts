import java.util.Base64
import java.util.Properties

// Upload key for Play: android/key.properties (gitignored; Codemagic writes it from its keystore secrets) with
// storeFile, storePassword, keyAlias, keyPassword. Without it, release builds fall back to the debug key so
// `flutter run --release` works locally; Play refuses debug-signed uploads, so that can't ship by accident.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// LINK_HOST from the build's --dart-define-from-file (env/prod.json, env/dev.json): Flutter hands Gradle every define,
// base64-encoded, as the dart-defines property. It becomes the App Link host in the manifest; without one the app
// claims a host that can't exist (.invalid), so no link opens it by mistake.
val linkHost = (project.findProperty("dart-defines") as String?).orEmpty().split(",")
    .map { String(Base64.getDecoder().decode(it)) } // `java.util` here would mean the Gradle `java` extension
    .firstOrNull { it.startsWith("LINK_HOST=") }?.substringAfter("=")
    ?.takeIf { Regex("^[a-z0-9.-]+$").matches(it) } ?: "links.invalid"

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shyammobiles.shyam_mobiles"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true // flutter_local_notifications (phone notifications while the app is open)
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once the first build is uploaded to Google Play.
        applicationId = "com.shyammobiles.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // flutter_secure_storage needs 23+, Credential Manager (Google sign-in) 24+
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["linkHost"] = linkHost
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
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
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // R8: shrink, optimise and obfuscate the Java/Kotlin side; Dart is obfuscated by the build flags (README).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
