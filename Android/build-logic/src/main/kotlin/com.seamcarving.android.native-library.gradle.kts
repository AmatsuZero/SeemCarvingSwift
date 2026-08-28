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
val minimumAndroidApi = 28
val swiftScratchDirectory = layout.buildDirectory.dir("swiftpm")
val generatedJniLibs = layout.buildDirectory.dir("generated/jniLibs")
val generatedSwiftJavaSources = layout.buildDirectory.dir("generated/swift-java")
val swiftKitCoreRuntimeSources = listOf(
    "org/swift/swiftkit/core/AutoSwiftMemorySession.java",
    "org/swift/swiftkit/core/CallTraces.java",
    "org/swift/swiftkit/core/ClosableSwiftArena.java",
    "org/swift/swiftkit/core/ConfinedSwiftMemorySession.java",
    "org/swift/swiftkit/core/JNISwiftInstance.java",
    "org/swift/swiftkit/core/JNISwiftInstanceCleanup.java",
    "org/swift/swiftkit/core/SwiftArena.java",
    "org/swift/swiftkit/core/SwiftInstance.java",
    "org/swift/swiftkit/core/SwiftInstanceCleanup.java",
    "org/swift/swiftkit/core/SwiftLibraries.java",
    "org/swift/swiftkit/core/SwiftMemoryManagement.java",
    "org/swift/swiftkit/core/SwiftObjects.java",
    "org/swift/swiftkit/core/ref/PhantomCleanable.java",
    "org/swift/swiftkit/core/ref/SwiftCleaner.java",
    "org/swift/swiftkit/core/util/PlatformUtils.java",
)

pluginManager.apply("com.android.library")
pluginManager.apply("com.seamcarving.android.toolchain")

extensions.configure<LibraryExtension> {
    namespace = "io.github.seamcarving"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 28
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets.getByName("main").jniLibs.srcDir(generatedJniLibs)
    sourceSets.getByName("main").java.srcDir(generatedSwiftJavaSources)
}

val generateSwiftJavaBindings = tasks.register("generateSwiftJavaBindings") {
    group = "build"
    description = "Generates the internal Java bindings for the Swift Android bridge."
    dependsOn("verifySwiftAndroidToolchain")
    inputs.file(File(swiftPackageDirectory, "Package.swift"))
    inputs.dir(File(swiftPackageDirectory, "Sources/SeamCarvingAndroidBridge"))
    outputs.dir(generatedSwiftJavaSources)

    doLast {
        project.exec {
            workingDir(swiftPackageDirectory)
            commandLine(
                swiftly,
                "run",
                "swift",
                "+$requiredSwift",
                "build",
                "--scratch-path",
                swiftScratchDirectory.get().asFile.absolutePath,
                "--product",
                "SeamCarvingAndroidBridge",
            )
        }

        val scratchDirectory = swiftScratchDirectory.get().asFile
        val generatedJavaSource = scratchDirectory
            .resolve("plugins/outputs")
            .walkTopDown()
            .filter { candidate ->
                candidate.isDirectory &&
                    candidate.invariantSeparatorsPath.endsWith(
                        "SeamCarvingAndroidBridge/destination/JExtractSwiftPlugin/src/generated/java",
                    )
            }
            .singleOrNull()
            ?: throw GradleException(
                "swift-java did not produce exactly one generated Java source directory for SeamCarvingAndroidBridge.",
            )
        val swiftKitCoreSource = scratchDirectory.resolve("checkouts")
            .listFiles()
            ?.map { checkout -> checkout.resolve("SwiftKitCore/src/main/java") }
            ?.singleOrNull(File::isDirectory)
            ?: throw GradleException("The pinned swift-java checkout did not contain SwiftKitCore sources.")

        val destination = generatedSwiftJavaSources.get().asFile
        destination.deleteRecursively()
        copy {
            from(generatedJavaSource)
            into(destination)
            filter { line: String ->
                line
                    .replace("import org.swift.swiftkit.core.util.*;", "")
                    .replace("import org.swift.swiftkit.core.collections.*;", "")
                    .replace("import org.swift.swiftkit.core.annotations.*;", "")
                    .replace("@Unsigned ", "")
                    .replace("@Unsigned", "")
            }
        }
        copy {
            from(swiftKitCoreSource) {
                include(swiftKitCoreRuntimeSources)
            }
            into(destination)
        }
    }
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("JavaWithJavac") }.configureEach {
    dependsOn(generateSwiftJavaBindings)
}

tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }.configureEach {
    dependsOn(generateSwiftJavaBindings)
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

val swiftBuildTasks = mutableListOf<Any>(generateSwiftJavaBindings)
val stageNativeLibraries = triples.map { (abi, triple) ->
    val taskNameSuffix = abi.split('-', '_').joinToString(separator = "") {
        it.replaceFirstChar(Char::uppercaseChar)
    }
    val bridgeLibrary = swiftScratchDirectory.get().asFile
        .resolve("$triple/release/libSeamCarvingAndroidBridge.so")
    val previousSwiftBuild = swiftBuildTasks.last()
    val buildBridge = tasks.register<Exec>("buildSwift${taskNameSuffix}") {
        group = "build"
        description = "Builds SeamCarvingAndroidBridge for Android $abi in release mode."
        dependsOn("verifySwiftAndroidToolchain", generateSwiftJavaBindings)
        mustRunAfter(previousSwiftBuild)
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
            "--scratch-path",
            swiftScratchDirectory.get().asFile.absolutePath,
            "--swift-sdk",
            triple,
            "--configuration",
            "release",
            "--product",
            "SeamCarvingAndroidBridge",
        )
    }
    swiftBuildTasks.add(buildBridge)

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
            val androidSystemLibraryDirectory = ndkPrebuilt.resolve(
                "sysroot/usr/lib/${ndkLibraryArchitectures.getValue(abi)}/$minimumAndroidApi",
            )
            check(androidSystemLibraryDirectory.isDirectory) {
                "Expected Android API $minimumAndroidApi system libraries at " +
                    "${androidSystemLibraryDirectory.absolutePath}."
            }

            val stagedRuntimeLibraries = mutableMapOf(
                bridgeLibrary.name to destination.resolve(bridgeLibrary.name),
                cxxShared.name to destination.resolve(cxxShared.name),
            )
            val pendingBinaries = ArrayDeque<File>()
            pendingBinaries.addAll(stagedRuntimeLibraries.values)
            while (pendingBinaries.isNotEmpty()) {
                readElfDependencies(readElf, pendingBinaries.removeFirst())
                    .forEach { libraryName ->
                        if (libraryName in stagedRuntimeLibraries) {
                            return@forEach
                        }
                        val source = listOf(
                            bridgeLibrary.parentFile.resolve(libraryName),
                            swiftRuntimeDirectory.resolve(libraryName),
                            cxxShared.parentFile.resolve(libraryName),
                        ).firstOrNull(File::isFile)
                        if (source == null && !androidSystemLibraryDirectory.resolve(libraryName).isFile) {
                            throw GradleException(
                                "Non-system DT_NEEDED dependency $libraryName is unavailable for $abi.",
                            )
                        }
                        if (source != null) {
                            val stagedLibrary = destination.resolve(libraryName)
                            source.copyTo(stagedLibrary, overwrite = true)
                            stagedRuntimeLibraries[libraryName] = stagedLibrary
                            pendingBinaries.add(stagedLibrary)
                        }
                    }
            }

            val unresolvedDependencies = stagedRuntimeLibraries.values.flatMap { binary ->
                readElfDependencies(readElf, binary)
                    .filterNot { dependency ->
                        dependency in stagedRuntimeLibraries ||
                            androidSystemLibraryDirectory.resolve(dependency).isFile
                    }
                    .map { dependency -> "${binary.name} -> $dependency" }
            }
            check(unresolvedDependencies.isEmpty()) {
                "Unresolved DT_NEEDED closure for $abi: ${unresolvedDependencies.joinToString()}."
            }
            check("libswiftCore.so" in stagedRuntimeLibraries) {
                "The Swift bridge did not resolve libswiftCore.so for $abi."
            }
            check("libSwiftJava.so" in stagedRuntimeLibraries) {
                "The generated JNI bridge did not resolve libSwiftJava.so for $abi."
            }
        }
    }
}

tasks.matching {
    it.name == "mergeDebugJniLibFolders" || it.name == "mergeReleaseJniLibFolders"
}.configureEach {
    dependsOn(stageNativeLibraries)
}
