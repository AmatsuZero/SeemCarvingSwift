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
}

tasks.register("verifyResolvedRuntime") {
    doLast {
        val resolvedNames = configurations.getByName("debugRuntimeClasspath")
            .resolve()
            .map { it.name }
            .toSet()
        listOf(
            "seamcarving-android-core",
            "seamcarving-android-bridge",
            "seamcarving-swiftkit-runtime",
        ).forEach { requiredArtifact ->
            check(resolvedNames.any { it.startsWith(requiredArtifact) }) {
                "External runtime classpath did not resolve $requiredArtifact: $resolvedNames"
            }
        }
    }
}
