package io.github.seamcarving.facade

import java.io.File
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PublicationGraphTest {
    private val repository = File(checkNotNull(System.getProperty("localMavenRepository")))
    private val version = checkNotNull(System.getProperty("seamcarvingVersion"))
    private val runtimeArtifacts = mapOf(
        "io.github.seamcarving:seamcarving-android-bridge" to version,
        "org.swift.swiftkit:swiftkit-core" to "1.0-SNAPSHOT",
    )

    @Test
    fun facadePomIncludesBitmapButExcludesMlKit() {
        val pom = pom("io.github.seamcarving", "seamcarving-android").readText()
        assertDependencyScope(pom, "seamcarving-android-core", "compile")
        assertDependencyScope(pom, "seamcarving-android-bitmap", "compile")
        assertFalse(pom.contains("seamcarving-android-mlkit"))
        assertFalse(pom.contains("face-detection"))
    }

    @Test
    fun publishedDependencyScopesMatchCapabilityBoundaries() {
        val bitmap = pom("io.github.seamcarving", "seamcarving-android-bitmap").readText()
        val mlKit = pom("io.github.seamcarving", "seamcarving-android-mlkit").readText()
        val core = pom("io.github.seamcarving", "seamcarving-android-core").readText()
        val bridge = pom("io.github.seamcarving", "seamcarving-android-bridge").readText()

        assertDependencyScope(bitmap, "seamcarving-android-core", "compile")
        assertFalse(bitmap.contains("face-detection"))
        assertDependencyScope(mlKit, "seamcarving-android-bitmap", "compile")
        assertDependencyScope(mlKit, "face-detection", "runtime")
        assertDependencyScope(core, "kotlinx-coroutines-core", "compile")
        assertDependencyScope(core, "seamcarving-android-bridge", "runtime")
        assertDependencyScope(core, "swiftkit-core", "runtime")
        assertDependencyScope(bridge, "swiftkit-core", "runtime")
    }

    @Test
    fun everyPublicCoordinatePublishesVersionedAarAndSources() {
        publicArtifacts.forEach { artifact ->
            val directory = artifactDirectory("io.github.seamcarving", artifact, version)
            assertEquals(version, pom("io.github.seamcarving", artifact).readVersion())
            assertTrue("Missing published $artifact AAR in $directory", latestArtifact(directory, ".aar") != null)
            assertTrue(
                "Missing published $artifact sources JAR in $directory",
                latestArtifact(directory, "-sources.jar") != null,
            )
        }
    }

    @Test
    fun privateRuntimeCoordinatesPublishPomJarAndSources() {
        runtimeArtifacts.forEach { (coordinate, runtimeVersion) ->
            val (group, artifact) = coordinate.split(':')
            val directory = artifactDirectory(group, artifact, runtimeVersion)
            assertTrue("Missing published $coordinate POM in $directory", latestArtifact(directory, ".pom") != null)
            assertTrue("Missing published $coordinate JAR in $directory", latestBinaryJar(directory) != null)
            assertTrue(
                "Missing published $coordinate sources JAR in $directory",
                latestArtifact(directory, "-sources.jar") != null,
            )
        }
    }

    @Test
    fun onlyPublishedCoreAarCarriesTheCompleteNativeAbiPack() {
        val coreAar = checkNotNull(
            latestArtifact(
                artifactDirectory("io.github.seamcarving", "seamcarving-android-core", version),
                ".aar",
            ),
        )
        val coreEntries = entries(coreAar)
        supportedAbis.forEach { abi ->
            assertTrue("Missing bridge for $abi", "jni/$abi/libSeamCarvingAndroidBridge.so" in coreEntries)
            assertTrue("Missing Swift runtime for $abi", "jni/$abi/libswiftCore.so" in coreEntries)
            assertTrue("Missing SwiftJava runtime for $abi", "jni/$abi/libSwiftJava.so" in coreEntries)
            assertTrue("Missing C++ runtime for $abi", "jni/$abi/libc++_shared.so" in coreEntries)
        }

        (publicArtifacts - "seamcarving-android-core").forEach { artifact ->
            val aar = checkNotNull(
                latestArtifact(artifactDirectory("io.github.seamcarving", artifact, version), ".aar"),
            )
            assertFalse("$artifact must not duplicate native libraries", entries(aar).any { it.startsWith("jni/") })
        }
    }

    private fun pom(group: String, artifact: String): File {
        val directory = artifactDirectory(group, artifact, version)
        return checkNotNull(latestArtifact(directory, ".pom")) {
            "Expected a published POM in $directory"
        }
    }

    private fun artifactDirectory(group: String, artifact: String, version: String): File =
        repository.resolve(group.replace('.', '/')).resolve(artifact).resolve(version)

    private fun latestArtifact(directory: File, suffix: String): File? = directory.listFiles()
        ?.filter { it.isFile && it.name.endsWith(suffix) && !it.name.endsWith(".sha1") && !it.name.endsWith(".md5") }
        ?.maxByOrNull(File::lastModified)

    private fun latestBinaryJar(directory: File): File? = directory.listFiles()
        ?.filter { it.isFile && it.name.endsWith(".jar") && !it.name.endsWith("-sources.jar") }
        ?.maxByOrNull(File::lastModified)

    private fun File.readVersion(): String =
        "<version>([^<]+)</version>".toRegex().find(readText())?.groupValues?.get(1)
            ?: error("No version element in $this")

    private fun assertDependencyScope(pom: String, artifact: String, scope: String) {
        val dependency = "<dependency>(.*?)</dependency>".toRegex(RegexOption.DOT_MATCHES_ALL)
            .findAll(pom)
            .map { it.value }
            .firstOrNull { it.contains("<artifactId>$artifact</artifactId>") }
        assertTrue("Missing dependency $artifact in POM:\n$pom", dependency != null)
        assertTrue(
            "Expected $artifact to use Maven $scope scope, found:\n$dependency",
            dependency?.contains("<scope>$scope</scope>") == true,
        )
    }

    private fun entries(archive: File): Set<String> = ZipFile(archive).use { zip ->
        zip.entries().asSequence().map { it.name }.toSet()
    }

    private companion object {
        val publicArtifacts = setOf(
            "seamcarving-android-core",
            "seamcarving-android-bitmap",
            "seamcarving-android-mlkit",
            "seamcarving-android",
        )
        val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86_64")
    }
}
