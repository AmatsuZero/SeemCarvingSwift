import org.gradle.api.tasks.compile.JavaCompile

plugins {
    `java-library`
    `maven-publish`
}

// This is a pinned, Android-specific subset vendored from swift-java 0.2.0.
// Publish it under the SeamCarving namespace rather than claiming the
// upstream Swift project's unpublished snapshot coordinate.
group = "io.github.seamcarving"
version = providers.gradleProperty("VERSION_NAME").get()

val coreProject = project(":seamcarving-android-core")
val swiftJavaCheckout = coreProject.layout.buildDirectory.dir("swiftpm/checkouts/swift-java")
val swiftKitCoreSources = swiftJavaCheckout.map { it.dir("SwiftKitCore/src/main/java") }
val generatedSources = layout.buildDirectory.dir("generated/swiftkit-core")
val androidJniRuntimeSources = listOf(
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

val stageSwiftKitCoreSources = tasks.register("stageSwiftKitCoreSources") {
    group = "build"
    description = "Stages the Android JNI subset of the pinned upstream SwiftKitCore sources."
    dependsOn(":seamcarving-android-core:generateSwiftJavaBindings")
    inputs.dir(swiftKitCoreSources)
    outputs.dir(generatedSources)

    doLast {
        val source = swiftKitCoreSources.get().asFile
        check(source.isDirectory) { "Pinned SwiftKitCore sources were not found at ${source.absolutePath}." }
        val destination = generatedSources.get().asFile
        destination.deleteRecursively()
        copy {
            from(source) {
                include(androidJniRuntimeSources)
            }
            into(destination)
        }
    }
}

sourceSets.main {
    java.srcDir(generatedSources)
}

tasks.withType<JavaCompile>().configureEach {
    dependsOn(stageSwiftKitCoreSources)
    options.release.set(11)
}

tasks.jar {
    dependsOn(stageSwiftKitCoreSources)
    archiveBaseName.set("seamcarving-swiftkit-runtime")
    from(swiftJavaCheckout.map { it.file("LICENSE.txt") }) {
        into("META-INF")
        rename { "LICENSE-swift-java.txt" }
    }
}

java {
    withSourcesJar()
}

tasks.named("sourcesJar") {
    dependsOn(stageSwiftKitCoreSources)
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            artifactId = "seamcarving-swiftkit-runtime"
            from(components["java"])
        }
    }
    repositories {
        maven {
            name = "Build"
            url = uri(rootProject.layout.buildDirectory.dir("local-maven"))
        }
    }
}
