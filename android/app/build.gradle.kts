import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

val localProperties = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

val releaseSigning = mapOf(
    "storeFile" to System.getenv("MYLEAFY_RELEASE_STORE_FILE"),
    "storePassword" to System.getenv("MYLEAFY_RELEASE_STORE_PASSWORD"),
    "keyAlias" to System.getenv("MYLEAFY_RELEASE_KEY_ALIAS"),
    "keyPassword" to System.getenv("MYLEAFY_RELEASE_KEY_PASSWORD"),
)
val isReleaseSigningConfigured = releaseSigning.values.all { !it.isNullOrBlank() }
val requestsReleaseBuild = gradle.startParameter.taskNames.any { task ->
    task.contains("Release", ignoreCase = true)
}
if (requestsReleaseBuild) {
    require(isReleaseSigningConfigured) {
        "Release build requires MYLEAFY_RELEASE_STORE_FILE, STORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD."
    }
    require(!localProperties.getProperty("SUPABASE_URL").isNullOrBlank()) {
        "Release build requires SUPABASE_URL in android/secrets.properties."
    }
    require(!localProperties.getProperty("SUPABASE_ANON_KEY").isNullOrBlank()) {
        "Release build requires SUPABASE_ANON_KEY in android/secrets.properties."
    }
}

android {
    namespace = "com.myleafy.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.myleafy.android"
        minSdk = 29
        targetSdk = 36
        versionCode = 2
        versionName = "1.0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField(
            "String",
            "SUPABASE_URL",
            "\"${localProperties.getProperty("SUPABASE_URL", "")}\"",
        )
        buildConfigField(
            "String",
            "SUPABASE_ANON_KEY",
            "\"${localProperties.getProperty("SUPABASE_ANON_KEY", "")}\"",
        )
    }

    signingConfigs {
        create("release") {
            if (isReleaseSigningConfigured) {
                storeFile = file(requireNotNull(releaseSigning["storeFile"]))
                storePassword = releaseSigning["storePassword"]
                keyAlias = releaseSigning["keyAlias"]
                keyPassword = releaseSigning["keyPassword"]
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (isReleaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    // 解析回归测试直接复用仓库根 contracts/ 下的教务 Fixture（单一事实来源）
    sourceSets {
        getByName("test") {
            resources.srcDir(rootProject.file("../contracts"))
        }
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive.navigation.suite)
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    implementation(libs.androidx.navigation.compose)

    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    implementation(libs.androidx.datastore.preferences)

    implementation(libs.okhttp)
    implementation(libs.jsoup)

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.auth)
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.functions)
    implementation(libs.ktor.client.android)
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.room.testing)
}
