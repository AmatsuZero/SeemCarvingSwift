import org.gradle.api.GradleException
import org.gradle.api.tasks.Exec
import java.io.ByteArrayOutputStream

val requiredSwift = "6.3.3"
val requiredSwiftSdk = "swift-6.3.3-RELEASE_android"
val requiredNdk = "27.3.13750724"
val swiftly = providers.environmentVariable("SWIFTLY_PATH").orNull ?: "swiftly"

fun runChecked(vararg command: String): String {
    val output = ByteArrayOutputStream()
    project.exec {
        commandLine(*command)
        standardOutput = output
        errorOutput = output
    }
    return output.toString(Charsets.UTF_8).also(::println)
}

val verifySwiftAndroidToolchain = tasks.register("verifySwiftAndroidToolchain") {
    group = "verification"
    description = "Verifies the pinned Swift, Android SDK, and NDK without downloading them."

    doLast {
        val swiftlyVersion = runChecked(swiftly, "--version")
        check(swiftlyVersion.isNotBlank()) { "Swiftly did not report a version." }

        val swiftVersion = runChecked(swiftly, "run", "swift", "+$requiredSwift", "--version")
        check(swiftVersion.contains(requiredSwift)) {
            "Expected Swift $requiredSwift, but received: $swiftVersion"
        }

        val installedSdks = runChecked(swiftly, "run", "swift", "+$requiredSwift", "sdk", "list")
        check(installedSdks.lineSequence().any { it.trim() == requiredSwiftSdk }) {
            "Required Swift SDK '$requiredSwiftSdk' is not installed."
        }

        val ndkHome = providers.environmentVariable("ANDROID_NDK_HOME").orNull
            ?: throw GradleException("ANDROID_NDK_HOME must point to Android NDK $requiredNdk.")
        val sourceProperties = file("$ndkHome/source.properties")
        check(sourceProperties.isFile) {
            "Android NDK source.properties not found at ${sourceProperties.absolutePath}."
        }
        val installedNdk = sourceProperties.readLines()
            .firstOrNull { it.trimStart().startsWith("Pkg.Revision") }
            ?.substringAfter('=')
            ?.trim()
            ?: throw GradleException("Pkg.Revision is missing from ${sourceProperties.absolutePath}.")
        check(installedNdk == requiredNdk) {
            "Expected Android NDK $requiredNdk, but found $installedNdk."
        }
    }
}

val swiftPackageDirectory = rootProject.projectDir.parentFile

tasks.register<Exec>("buildSwiftArm64-v8a") {
    group = "build"
    description = "Builds SeamCarvingAndroidBridge for Android arm64-v8a."
    dependsOn(verifySwiftAndroidToolchain)
    workingDir(swiftPackageDirectory)
    commandLine(
        swiftly,
        "run",
        "swift",
        "+$requiredSwift",
        "build",
        "--swift-sdk",
        "aarch64-unknown-linux-android28",
        "--build-system",
        "native",
        "--target",
        "SeamCarvingAndroidBridge",
    )
}
