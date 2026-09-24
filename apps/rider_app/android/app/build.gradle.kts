import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps SDK key, read from android/secrets.properties (gitignored) and
// injected as the ${MAPS_API_KEY} manifest placeholder. Empty when absent so the
// build never fails on a missing key (the map just won't render).
val mapsSecretsFile = rootProject.file("secrets.properties")
val mapsApiKey: String = Properties().apply {
    if (mapsSecretsFile.exists()) mapsSecretsFile.inputStream().use { load(it) }
}.getProperty("MAPS_API_KEY") ?: ""

// Visual Direction v2 variant builds (--dart-define=THEME=midnight|daylight|
// daynight) install as separate apps with their own name, so the three looks
// can sit side by side on one phone. Flutter hands dart-defines to Gradle as
// base64 in the "dart-defines" property. The default/turquoise/mono builds
// keep the normal ID, so they update the installed app as before.
val themeVariant: String = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.map { d: String -> String(Base64.getDecoder().decode(d), Charsets.UTF_8) }
    ?.firstOrNull { d: String -> d.startsWith("THEME=") }
    ?.removePrefix("THEME=")
    ?: ""
val variantLabel: String? = mapOf(
    "midnight" to "RideVela A · Midnight",
    "daylight" to "RideVela B · Daylight",
    "daynight" to "RideVela C · Day&Night",
    "local" to "RideVela D · Local",
    "ink" to "RideVela E · Ink",
    "glass" to "RideVela F · Glass",
    "indigo" to "RideVela · Indigo",
    "lapis" to "RideVela · Lapis",
    "marigold" to "RideVela · Marigold",
    "copper" to "RideVela · Copper",
    "garnet" to "RideVela · Garnet",
)[themeVariant]

android {
    namespace = "in.novarobotics.ubernav.rider_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.novarobotics.ubernav.rider_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        manifestPlaceholders["appLabel"] = variantLabel ?: "RideVela Rider"
        if (variantLabel != null) applicationIdSuffix = ".$themeVariant"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // The flutter_stripe plugin's release lint (:stripe_android:lintVitalAnalyzeRelease)
    // pulls a lint-only classpath needing com.google.android.gms:play-services-tapandpay,
    // which isn't always resolvable here — and lint is static analysis of the plugin, not
    // required for a working APK. Skip release lint so a green build doesn't hinge on
    // fetching that artifact.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
