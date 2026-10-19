import com.android.build.api.dsl.ApplicationExtension
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. The shared builder (flutter-build.yml, pinned in
// .github/workflows/manual-build.yml) decodes ANDROID_KEYSTORE_BASE64 into
// android/app/upload-keystore.jks and writes android/key.properties before Gradle
// is configured; a local release build reads the same file when a developer has
// one. Both paths are git-ignored. Explicit imports avoid the Gradle java
// extension shadowing the java package name in this Kotlin script.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

extensions.configure<ApplicationExtension> {
    namespace = "com.keshabstudios.karmopath"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications scheduled notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.keshabstudios.karmopath"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Guarded: a checkout with no key.properties (a plain
            // `flutter run --release` on a fresh machine) still configures. CI
            // writes the file before this is evaluated, so the guard passes there.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // AGP 9 turns R8 on for release by default. R8 renames
            // kotlin.coroutines.Continuation (seen as `i5` in the dex), but
            // Pigeon's native-interop path — the one shared_preferences_android
            // uses for its async API — resolves Java methods by their exact JVM
            // descriptor, so every preferences read failed on device with
            // java.lang.NoSuchMethodError: ...getStringList(...Continuation;)...
            // Keep release unshrunk until keep rules cover JNI lookups; the
            // alternative is a mapping that breaks again with the next plugin.
            isMinifyEnabled = false
            isShrinkResources = false
            // Without this the release artifact stays unsigned and Play rejects
            // the upload. Only wired up when the upload key is actually present.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
