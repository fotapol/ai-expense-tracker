import java.io.File
import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(propertyName: String, envName: String): String {
    val propertyValue = keystoreProperties.getProperty(propertyName)?.trim().orEmpty()
    if (propertyValue.isNotEmpty()) {
        return propertyValue
    }
    return System.getenv(envName)?.trim().orEmpty()
}

fun resolveReleaseStoreFile(rawStoreFile: String): File? {
    if (rawStoreFile.isBlank()) {
        return null
    }
    val candidate = File(rawStoreFile)
    return if (candidate.isAbsolute) candidate else project.file(rawStoreFile)
}

val releaseStoreFileValue = signingValue("storeFile", "ANDROID_KEYSTORE_FILE")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseStoreFile = resolveReleaseStoreFile(releaseStoreFileValue)

android {
    namespace = "com.example.expense_tracker_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nexavend.expense_tracker_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseStoreFile?.let { storeFile = it }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task -> task.name.contains("Release") }
    if (!buildingRelease) {
        return@whenReady
    }

    val missing = mutableListOf<String>()
    if (releaseStoreFileValue.isBlank()) missing += "storeFile or ANDROID_KEYSTORE_FILE"
    if (releaseStorePassword.isBlank()) missing += "storePassword or ANDROID_KEYSTORE_PASSWORD"
    if (releaseKeyAlias.isBlank()) missing += "keyAlias or ANDROID_KEY_ALIAS"
    if (releaseKeyPassword.isBlank()) missing += "keyPassword or ANDROID_KEY_PASSWORD"
    if (missing.isNotEmpty()) {
        throw GradleException(
            "Release signing is incomplete. Missing: ${missing.joinToString(", ")}. " +
                "Copy android/key.properties.example to android/key.properties or set the Android signing environment variables."
        )
    }
    if (releaseKeyAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("Release builds must not use the debug signing key alias androiddebugkey.")
    }
    if (releaseStoreFile == null || !releaseStoreFile.isFile) {
        throw GradleException(
            "Release keystore file was not found. Relative storeFile paths resolve from android/app: $releaseStoreFileValue"
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
