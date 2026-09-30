plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.roborazzi)
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

}

android {
    namespace = "com.myleafy.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.myleafy.android"
        minSdk = 29
        targetSdk = 36
        versionCode = 4
        versionName = "1.2.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "MYLEAFY_API_ORIGIN", "\"${providers.gradleProperty("myleafyApiOrigin").getOrElse("https://api.myleafy.space")}\"")
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
        debug {
            applicationIdSuffix = ".next"
            versionNameSuffix = "-debug"
        }
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

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
            all {
                it.systemProperties["robolectric.pixelCopyRenderMode"] = "hardware"
                it.systemProperties["user.language"] = "zh"
                it.systemProperties["user.country"] = "CN"
                it.systemProperties["user.timezone"] = "Asia/Shanghai"
                it.systemProperties["cloudflareStagingCheck"] = project.hasProperty("cloudflareStagingCheck").toString()
                it.useJUnit {
                    if (project.hasProperty("screenshot")) {
                        includeCategories("com.myleafy.android.testing.ScreenshotTests")
                    } else {
                        excludeCategories("com.myleafy.android.testing.ScreenshotTests")
                    }
                }
            }
        }
    }

    // 解析回归测试直接复用仓库根 contracts/ 下的教务 Fixture（单一事实来源）
    sourceSets {
        getByName("test") {
            resources.srcDir(rootProject.file("../contracts"))
        }
        getByName("androidTest") {
            assets.srcDir("$projectDir/schemas")
        }
    }
}

roborazzi {
    outputDir.set(file("src/test/screenshots"))
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation("com.google.mlkit:text-recognition:16.0.1")
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
    implementation(libs.androidx.work.runtime)

implementation(libs.okhttp)
implementation(libs.coil)
implementation(libs.jsoup)

    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.ext.junit)
    testImplementation(libs.androidx.test.runner)
    testImplementation(libs.roborazzi.core)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
    testImplementation(libs.robolectric)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.room.testing)
    androidTestImplementation(libs.androidx.work.testing)
}
