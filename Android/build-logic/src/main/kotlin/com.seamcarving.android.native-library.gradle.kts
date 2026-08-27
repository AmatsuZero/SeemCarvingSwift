import com.android.build.api.dsl.LibraryExtension
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.ArrayDeque
import org.gradle.api.GradleException
import org.gradle.api.tasks.Exec
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.register

val triples = mapOf(
    "arm64-v8a" to "aarch64-unknown-linux-android28",
    "armeabi-v7a" to "armv7-unknown-linux-android28",
    "x86_64" to "x86_64-unknown-linux-android28",
)

val swiftRuntimeArchitectures = mapOf(
    "arm64-v8a" to "aarch64",
    "armeabi-v7a" to "armv7",
    "x86_64" to "x86_64",
)

val ndkLibraryArchitectures = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "arm-linux-androideabi",
    "x86_64" to "x86_64-linux-android",
)

val requiredSwift = "6.3.3"
val swiftly = providers.environmentVariable("SWIFTLY_PATH").orNull ?: "swiftly"
val swiftPackageDirectory = rootProject.projectDir.parentFile
val generatedJniLibs = layout.buildDirectory.dir("generated/jniLibs")

pluginManager.apply("com.android.library")
pluginManager.apply("com.seamcarving.android.toolchain")

extensions.configure<LibraryExtension> {
    namespace = "com.seamcarving.android.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 28
    }

    sourceSets.getByName("main").jniLibs.srcDir(generatedJniLibs)
}

fun androidNdkHome(): File = providers.environmentVariable("ANDROID_NDK_HOME").orNull
    ?.let(::file)
    ?: throw GradleException("ANDROID_NDK_HOME must point to the pinned Android NDK.")

fun readElfDependencies(readElf: File, binary: File): Set<String> {
    val output = ByteArrayOutputStream()
    project.exec {
        commandLine(readElf.absolutePath, "--dynamic-table", binary.absolutePath)
        standardOutput = output
        errorOutput = output
    }
    return "Shared library: \\[([^]]+)]".toRegex()
        .findAll(output.toString(Charsets.UTF_8))
        .map { it.groupValues[1] }
        .toSet()
}

val stageNativeLibraries = triples.map { (abi, triple) ->
    val taskNameSuffix = abi.split('-', '_').joinToString(separator = "") {
        it.replaceFirstChar(Char::uppercaseChar)
    }
    val bridgeLibrary = File(
        swiftPackageDirectory,
        ".build/$triple/release/libSeamCarvingAndroidBridge.so",
    )
    val buildBridge = tasks.register<Exec>("buildSwift${taskNameSuffix}") {
        group = "build"
        description = "Builds SeamCarvingAndroidBridge for Android $abi in release mode."
        dependsOn("verifySwiftAndroidToolchain")
        workingDir(swiftPackageDirectory)
        inputs.file(File(swiftPackageDirectory, "Package.swift"))
        inputs.file(File(swiftPackageDirectory, "Package.resolved"))
        inputs.dir(File(swiftPackageDirectory, "Sources"))
        outputs.file(bridgeLibrary)
        commandLine(
            swiftly,
            "run",
            "swift",
            "+$requiredSwift",
            "build",
            "--swift-sdk",
            triple,
            "--configuration",
            "release",
            "--product",
            "SeamCarvingAndroidBridge",
        )
    }

    tasks.register("stageSwift${taskNameSuffix}NativeLibraries") {
        group = "build"
        description = "Stages the required Android native libraries for $abi."
        dependsOn(buildBridge)
        outputs.dir(generatedJniLibs.map { it.dir(abi) })

        doLast {
            val ndkHome = androidNdkHome()
            val ndkPrebuilt = ndkHome.resolve("toolchains/llvm/prebuilt")
                .listFiles()
                ?.singleOrNull(File::isDirectory)
                ?: throw GradleException("Could not locate the NDK host toolchain in $ndkHome.")
            val readElf = ndkPrebuilt.resolve("bin/llvm-readelf")
            check(readElf.isFile) { "Could not locate llvm-readelf at ${readElf.absolutePath}." }
            check(bridgeLibrary.isFile) { "Expected Swift bridge at ${bridgeLibrary.absolutePath}." }

            val destination = generatedJniLibs.get().dir(abi).asFile
            destination.deleteRecursively()
            check(destination.mkdirs()) { "Could not create ${destination.absolutePath}." }

            bridgeLibrary.copyTo(destination.resolve(bridgeLibrary.name), overwrite = true)
            val cxxShared = ndkPrebuilt.resolve(
                "sysroot/usr/lib/${ndkLibraryArchitectures.getValue(abi)}/libc++_shared.so",
            )
            check(cxxShared.isFile) { "Expected NDK runtime at ${cxxShared.absolutePath}." }
            cxxShared.copyTo(destination.resolve(cxxShared.name), overwrite = true)

            val swiftRuntimeDirectory = ndkHome.parentFile.resolve(
                "swift-resources/usr/lib/swift-${swiftRuntimeArchitectures.getValue(abi)}/android",
            )
            check(swiftRuntimeDirectory.isDirectory) {
                "Expected Swift Android runtime directory at ${swiftRuntimeDirectory.absolutePath}."
            }

            val copiedSwiftLibraries = mutableSetOf<String>()
            val pendingBinaries = ArrayDeque<File>()
            pendingBinaries.add(bridgeLibrary)
            while (pendingBinaries.isNotEmpty()) {
                readElfDependencies(readElf, pendingBinaries.removeFirst())
                    .filter { it.startsWith("libswift") && it.endsWith(".so") }
                    .forEach { libraryName ->
                        if (copiedSwiftLibraries.add(libraryName)) {
                            val source = swiftRuntimeDirectory.resolve(libraryName)
                            check(source.isFile) {
                                "Swift runtime dependency $libraryName is unavailable at ${source.absolutePath}."
                            }
                            source.copyTo(destination.resolve(libraryName), overwrite = true)
                            pendingBinaries.add(source)
                        }
                    }
            }
            check("libswiftCore.so" in copiedSwiftLibraries) {
                "The Swift bridge did not resolve libswiftCore.so for $abi."
            }
        }
    }
}

tasks.matching { it.name == "mergeReleaseJniLibFolders" }.configureEach {
    dependsOn(stageNativeLibraries)
}
