import org.gradle.api.tasks.Exec

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
}

tasks.register("publishAllPublicationsToBuildRepository") {
    group = "publishing"
    description = "Publishes the complete Android artifact graph to build/local-maven."
    dependsOn(
        ":swiftkit-core:publishMavenPublicationToBuildRepository",
        ":seamcarving-android-bridge:publishMavenPublicationToBuildRepository",
        ":seamcarving-android-core:publishReleasePublicationToBuildRepository",
        ":seamcarving-android-bitmap:publishReleasePublicationToBuildRepository",
        ":seamcarving-android-mlkit:publishReleasePublicationToBuildRepository",
        ":seamcarving-android:publishReleasePublicationToBuildRepository",
    )
}

val externalMavenSample = layout.projectDirectory.dir("sample")
tasks.register<Exec>("verifyExternalMavenSample") {
    group = "verification"
    description = "Builds and runs the standalone sample using only locally published Maven coordinates."
    dependsOn("publishAllPublicationsToBuildRepository")
    workingDir(externalMavenSample)
    environment.remove("ANDROID_NDK_HOME")
    environment.remove("SWIFTLY_PATH")
    commandLine(
        layout.projectDirectory.file("gradlew").asFile.absolutePath,
        "--no-daemon",
        "--refresh-dependencies",
        "-p",
        externalMavenSample.asFile.absolutePath,
        "clean",
        "connectedDebugAndroidTest",
        "verifyMavenCoordinates",
        "-PseamcarvingRepository=${layout.buildDirectory.dir("local-maven").get().asFile.toURI()}",
        "-PseamcarvingVersion=${providers.gradleProperty("VERSION_NAME").get()}",
    )
}
