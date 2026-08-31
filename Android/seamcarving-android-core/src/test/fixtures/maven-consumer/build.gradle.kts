plugins {
    id("com.android.application") version "8.10.1"
}

android {
    namespace = "io.github.seamcarving.consumer"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.seamcarving.consumer"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
}

dependencies {
    implementation(
        "io.github.seamcarving:seamcarving-android-core:" +
            providers.gradleProperty("seamcarvingVersion").get(),
    )
    // A consumer may already depend directly on the canonical upstream runtime.
    // This must resolve to the same Maven component used by SeamCarving.
    implementation("org.swift.swiftkit:swiftkit-core:1.0-SNAPSHOT")
}

tasks.register("verifyResolvedRuntime") {
    doLast {
        val runtimeClasspath = configurations.getByName("debugRuntimeClasspath")
        val resolvedNames = runtimeClasspath.resolve()
            .map { it.name }
            .toSet()
        listOf(
            "seamcarving-android-core",
            "seamcarving-android-bridge",
            "swiftkit-core",
        ).forEach { requiredArtifact ->
            check(resolvedNames.any { it.startsWith(requiredArtifact) }) {
                "External runtime classpath did not resolve $requiredArtifact: $resolvedNames"
            }
        }
        val swiftKitComponents = runtimeClasspath.incoming.resolutionResult.allComponents
            .mapNotNull { it.moduleVersion }
            .filter { it.group == "org.swift.swiftkit" && it.name == "swiftkit-core" }
        check(swiftKitComponents.size == 1) {
            "Expected one canonical SwiftKitCore component, resolved $swiftKitComponents"
        }
        check(resolvedNames.none { it.startsWith("seamcarving-swiftkit-runtime") }) {
            "A second project-owned SwiftKit runtime would duplicate upstream classes: $resolvedNames"
        }
    }
}
