import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.artifacts.Configuration
import org.gradle.api.tasks.testing.Test
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

group = "io.github.seamcarving"
version = providers.gradleProperty("VERSION_NAME").get()

extensions.configure<LibraryExtension> {
    namespace = "io.github.seamcarving.mlkit"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 28
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    api(project(":seamcarving-android-bitmap"))
    implementation(libs.mlkit.face.detection)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    androidTestImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.runner)
}

tasks.withType<Test>().configureEach {
    if (name == "testReleaseUnitTest") {
        dependsOn("bundleReleaseAar")
        systemProperty(
            "releaseAar",
            layout.buildDirectory.file(
                "outputs/aar/seamcarving-android-mlkit-release.aar",
            ).get().asFile,
        )
    } else {
        exclude("**/MlKitAarContentsTest.class")
    }
}

evaluationDependsOn(":seamcarving-android-core")
evaluationDependsOn(":seamcarving-android-bitmap")

afterEvaluate {
    val coreDebugRuntime = project(":seamcarving-android-core")
        .configurations.getByName("debugRuntimeClasspath")
    val bitmapDebugRuntime = project(":seamcarving-android-bitmap")
        .configurations.getByName("debugRuntimeClasspath")
    val mlKitDebugRuntime = configurations.getByName("debugRuntimeClasspath")

    tasks.withType<Test>().configureEach {
        doFirst {
            systemProperty("coreRuntimeCoordinates", coreDebugRuntime.coordinates())
            systemProperty("bitmapRuntimeCoordinates", bitmapDebugRuntime.coordinates())
            systemProperty("mlKitRuntimeCoordinates", mlKitDebugRuntime.coordinates())
        }
    }
}

fun Configuration.coordinates(): String = incoming.resolutionResult.allComponents
    .mapNotNull { component -> component.moduleVersion?.toString() }
    .distinct()
    .sorted()
    .joinToString("\n")
