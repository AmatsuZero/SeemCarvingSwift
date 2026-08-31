import org.gradle.api.tasks.compile.JavaCompile

plugins {
    `java-library`
    `maven-publish`
}

// This is the Android-compatible subset of the pinned swift-java 0.2.0
// SwiftKitCore module. It intentionally retains the exact upstream component
// identity so Gradle selects one SwiftKitCore component when consumers also
// depend on the canonical runtime; publishing the same classes under another
// GAV would create duplicate-class failures.
group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

val coreProject = project(":seamcarving-android-core")
val swiftJavaCheckout = coreProject.layout.buildDirectory.dir("swiftpm/checkouts/swift-java")
val swiftKitCoreSources = swiftJavaCheckout.map { it.dir("SwiftKitCore/src/main/java") }
val swiftKitCoreBuild = swiftJavaCheckout.map { it.file("SwiftKitCore/build.gradle.kts") }
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
    inputs.file(swiftKitCoreBuild)
    outputs.dir(generatedSources)

    doLast {
        val source = swiftKitCoreSources.get().asFile
        check(source.isDirectory) { "Pinned SwiftKitCore sources were not found at ${source.absolutePath}." }
        val upstreamBuild = swiftKitCoreBuild.get().asFile.readText()
        check(upstreamBuild.contains("group = \"${project.group}\"")) {
            "Pinned SwiftKitCore changed its upstream Maven group; update the canonical Android runtime identity."
        }
        check(upstreamBuild.contains("version = \"${project.version}\"")) {
            "Pinned SwiftKitCore changed its upstream Maven version; update the canonical Android runtime identity."
        }
        check(upstreamBuild.contains("artifactId = \"swiftkit-core\"")) {
            "Pinned SwiftKitCore changed its upstream Maven artifact ID."
        }
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
    archiveBaseName.set("swiftkit-core")
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
            artifactId = "swiftkit-core"
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
