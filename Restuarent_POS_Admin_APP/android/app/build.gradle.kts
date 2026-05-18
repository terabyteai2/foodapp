import java.util.Properties
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val isReleaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else if (isReleaseBuildRequested) {
    throw GradleException(
        "Release signing is not configured. Create android/key.properties and an upload keystore before building release."
    )
}

fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

fun String.toColonFingerprint(): String =
    chunked(2).joinToString(":") { it.uppercase() }

fun releaseCertificateDigest(algorithm: String): String {
    val storeFile = keystoreProperties["storeFile"] as String?
        ?: throw GradleException("Release signing storeFile is missing in android/key.properties.")
    val storePassword = keystoreProperties["storePassword"] as String?
        ?: throw GradleException("Release signing storePassword is missing in android/key.properties.")
    val keyAlias = keystoreProperties["keyAlias"] as String?
        ?: throw GradleException("Release signing keyAlias is missing in android/key.properties.")
    val keystoreFile = project.file(storeFile)
    if (!keystoreFile.exists()) {
        throw GradleException("Release keystore not found: ${keystoreFile.path}")
    }

    val keyStore = KeyStore.getInstance(KeyStore.getDefaultType())
    keystoreFile.inputStream().use { input ->
        keyStore.load(input, storePassword.toCharArray())
    }
    val certificate = keyStore.getCertificate(keyAlias)
        ?: throw GradleException("Release signing certificate alias '$keyAlias' was not found.")
    return MessageDigest.getInstance(algorithm).digest(certificate.encoded).toHex()
}

android {
    namespace = "com.terabyteAI.Res.Admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.terabyteAI.Res.Admin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

val verifyReleaseGoogleSignInSha by tasks.registering {
    group = "verification"
    description = "Checks that google-services.json contains this release keystore SHA-1."
    onlyIf { isReleaseBuildRequested }

    doLast {
        val googleServicesFile = project.file("google-services.json")
        if (!googleServicesFile.exists()) {
            throw GradleException("android/app/google-services.json is missing.")
        }

        val releaseSha1 = releaseCertificateDigest("SHA-1")
        val releaseSha256 = releaseCertificateDigest("SHA-256")
        val configuredHashes = Regex("\"certificate_hash\"\\s*:\\s*\"([0-9a-fA-F]+)\"")
            .findAll(googleServicesFile.readText())
            .map { it.groupValues[1].lowercase() }
            .toSet()

        if (!configuredHashes.contains(releaseSha1)) {
            throw GradleException(
                """
                Release Google Sign-In SHA mismatch.
                Add this Android app fingerprint in Firebase for package com.terabyteAI.Res.Admin, then download the updated google-services.json.
                SHA-1: ${releaseSha1.toColonFingerprint()}
                SHA-256: ${releaseSha256.toColonFingerprint()}
                """.trimIndent()
            )
        }
    }
}

gradle.projectsEvaluated {
    tasks.findByName("preReleaseBuild")?.dependsOn(verifyReleaseGoogleSignInSha)
}
