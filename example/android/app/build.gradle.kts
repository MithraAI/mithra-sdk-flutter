plugins {
    id("com.android.application")
    // Applied explicitly, not left to the Flutter Gradle Plugin to pull in.
    // settings.gradle.kts declares it with `apply false`, so without this line
    // the :app project never gets the Kotlin plugin of its own accord. Current
    // stable Flutter happens to apply it transitively, which makes the
    // `kotlin { }` extension below resolve; the declared floor (Flutter 3.41)
    // does not, and the build fails there with "Unresolved reference
    // 'compilerOptions'". Applying it here pins the version settings.gradle.kts
    // declares on every supported toolchain.
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mithra.flutter.sdk.example"
    compileSdk = flutter.compileSdkVersion
    // Pinned to a locally installed NDK; flutter.ndkVersion may not be installed.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mithra.flutter.sdk.example"
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

flutter {
    source = "../.."
}
