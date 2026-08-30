plugins {
    id("com.android.application") version "8.10.1"
    id("org.jetbrains.kotlin.android") version "2.1.21"
}

val seamcarvingVersion = providers.gradleProperty("seamcarvingVersion")
    .orElse(providers.gradleProperty("VERSION_NAME"))
    .get()
val seamcarvingGroup = "io.github.seamcarving"
val mlKitSample by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

android {
    namespace = "io.github.seamcarving.sample"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.seamcarving.sample"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("$seamcarvingGroup:seamcarving-android:$seamcarvingVersion")
    mlKitSample("$seamcarvingGroup:seamcarving-android-mlkit:$seamcarvingVersion")
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

tasks.register("verifyMavenCoordinates") {
    group = "verification"
    description = "Verifies default and optional Maven graphs without Gradle project dependencies."
    doLast {
        val defaultRuntime = configurations.getByName("debugRuntimeClasspath")
        val defaultCoordinates = defaultRuntime.coordinates()
        val optionalCoordinates = mlKitSample.coordinates()

        setOf(
            "$seamcarvingGroup:seamcarving-android:$seamcarvingVersion",
            "$seamcarvingGroup:seamcarving-android-core:$seamcarvingVersion",
            "$seamcarvingGroup:seamcarving-android-bitmap:$seamcarvingVersion",
            "$seamcarvingGroup:seamcarving-android-bridge:$seamcarvingVersion",
            "org.swift.swiftkit:swiftkit-core:1.0-SNAPSHOT",
        ).forEach { required ->
            check(required in defaultCoordinates) {
                "Default Maven graph did not resolve $required: $defaultCoordinates"
            }
        }
        check(defaultCoordinates.none { it.contains("seamcarving-android-mlkit") || it.contains("face-detection") }) {
            "Default facade unexpectedly resolved ML Kit: $defaultCoordinates"
        }
        check("$seamcarvingGroup:seamcarving-android-mlkit:$seamcarvingVersion" in optionalCoordinates) {
            "Optional Maven graph did not resolve the ML Kit adapter: $optionalCoordinates"
        }
        check("com.google.mlkit:face-detection:16.1.7" in optionalCoordinates) {
            "Optional Maven graph did not resolve pinned ML Kit face detection: $optionalCoordinates"
        }
        check(defaultRuntime.projectSelections().isEmpty()) {
            "The sample resolved Gradle projects instead of Maven modules: ${defaultRuntime.projectSelections()}"
        }
        check(mlKitSample.projectSelections().isEmpty()) {
            "The optional sample graph resolved Gradle projects: ${mlKitSample.projectSelections()}"
        }
    }
}

if (rootProject != project) {
    tasks.matching {
        it.name == "connectedDebugAndroidTest" || it.name == "verifyMavenCoordinates"
    }.configureEach {
        dependsOn(rootProject.tasks.named("publishAllPublicationsToBuildRepository"))
    }
}

fun org.gradle.api.artifacts.Configuration.coordinates(): Set<String> =
    incoming.resolutionResult.allComponents
        .mapNotNull { it.moduleVersion?.toString() }
        .toSet()

fun org.gradle.api.artifacts.Configuration.projectSelections(): Set<String> =
    incoming.resolutionResult.allDependencies
        .filterIsInstance<org.gradle.api.artifacts.result.ResolvedDependencyResult>()
        .map { it.selected.id }
        .filterIsInstance<org.gradle.api.artifacts.component.ProjectComponentIdentifier>()
        .map { it.projectPath }
        .toSet()
