import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val mapsSecretsProperties = Properties()
val mapsSecretsFile = rootProject.file("secrets.properties")
if (mapsSecretsFile.exists()) {
    mapsSecretsProperties.load(FileInputStream(mapsSecretsFile))
}

val googleMapsApiKey =
    providers.gradleProperty("GOOGLE_MAPS_API_KEY").orNull
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: System.getenv("ANDROID_GOOGLE_MAPS_API_KEY")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        ?: mapsSecretsProperties.getProperty("GOOGLE_MAPS_API_KEY")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        ?: throw GradleException(
            "Missing Android Google Maps API key. Set ANDROID_GOOGLE_MAPS_API_KEY, " +
                "-PGOOGLE_MAPS_API_KEY, or android/secrets.properties.",
        )

android {
    namespace = "com.brightminds.kmstry"
    compileSdk = flutter.compileSdkVersion
    // Release strip adımında NDK yolu sapmaması için sabit sürüm kullanıyoruz.
    ndkVersion = "27.0.12077973"

   compileOptions {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
    isCoreLibraryDesugaringEnabled = true
}

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.brightminds.kmstry"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
    }
signingConfigs {
    create("release") {
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
    }
}
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("release")  
                }
    }
}

flutter {
    source = "../.."
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Native, donanım hızlandırmalı video düzenleme (ön kamera ayna).
    // Google resmi Media3 Transformer — ffmpeg gerekmez, re-encode GPU üzerinde.
    implementation("androidx.media3:media3-transformer:1.4.1")
    implementation("androidx.media3:media3-effect:1.4.1")
    implementation("androidx.media3:media3-common:1.4.1")
}
