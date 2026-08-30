package io.github.seamcarving.mlkit

import java.io.DataInputStream
import java.io.File
import java.nio.file.Files
import java.util.jar.JarInputStream
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MlKitAarContentsTest {
    @Test
    fun releaseAarContainsAdapterCodeButNoNativeLibraries() {
        val releaseAar = File(checkNotNull(System.getProperty("releaseAar")))
        assertTrue("Expected release AAR at $releaseAar", releaseAar.isFile)

        val entries = ZipFile(releaseAar).use { archive ->
            archive.entries().asSequence().map { it.name }.toSet()
        }

        assertTrue("classes.jar" in entries)
        assertFalse(entries.any { it.startsWith("jni/") || it.endsWith(".so") })
    }

    @Test
    fun releaseAarDoesNotExposeDetectorOrRasterizerImplementationTypes() {
        val releaseAar = File(checkNotNull(System.getProperty("releaseAar")))
        val implementationTypes = setOf(
            "io/github/seamcarving/mlkit/FaceBoxDetector.class",
            "io/github/seamcarving/mlkit/FaceBoxDetectorFactory.class",
            "io/github/seamcarving/mlkit/FaceProtectionMask.class",
        )

        ZipFile(releaseAar).use { archive ->
            val classesJar = checkNotNull(archive.getEntry("classes.jar"))
            JarInputStream(archive.getInputStream(classesJar)).use { jar ->
                while (true) {
                    val entry = jar.nextJarEntry ?: break
                    if (entry.name in implementationTypes) {
                        val accessFlags = DataInputStream(jar).readClassAccessFlags()
                        assertFalse(
                            "ML Kit implementation type is JVM-public: ${entry.name}",
                            accessFlags and PUBLIC_ACCESS != 0,
                        )
                    }
                }
            }
        }
    }

    @Test
    fun releaseAarPublicMethodsDoNotReferencePrivateImplementationTypes() {
        val releaseAar = File(checkNotNull(System.getProperty("releaseAar")))
        val classesJar = Files.createTempFile("seamcarving-mlkit-release", ".jar")
        ZipFile(releaseAar).use { archive ->
            val entry = checkNotNull(archive.getEntry("classes.jar"))
            archive.getInputStream(entry).use { input ->
                Files.newOutputStream(classesJar).use(input::transferTo)
            }
        }

        val javap = File(System.getProperty("java.home"), "bin/javap")
        assertTrue("Release API test requires javap at $javap", javap.canExecute())
        val process = ProcessBuilder(
            javap.absolutePath,
            "-private",
            "-classpath",
            classesJar.toString(),
            "io.github.seamcarving.mlkit.FaceProtectionMaskKt",
        ).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        assertEquals("javap failed:\n$output", 0, process.waitFor())

        val leakingMethods = output.lineSequence()
            .map(String::trim)
            .filter { line ->
                line.startsWith("public ") && line.contains('(') &&
                    PRIVATE_IMPLEMENTATION_TYPES.any(line::contains)
            }
            .toList()
        assertTrue(
            "Release AAR public methods reference private implementation types: $leakingMethods",
            leakingMethods.isEmpty(),
        )
    }
}

private fun DataInputStream.readClassAccessFlags(): Int {
    require(readInt() == CLASS_FILE_MAGIC) { "Expected a JVM class file." }
    readUnsignedShort()
    readUnsignedShort()
    val constantPoolCount = readUnsignedShort()
    var index = 1
    while (index < constantPoolCount) {
        when (readUnsignedByte()) {
            1 -> skipBytes(readUnsignedShort())
            3, 4, 9, 10, 11, 12, 17, 18 -> skipBytes(4)
            5, 6 -> {
                skipBytes(8)
                index++
            }
            7, 8, 16, 19, 20 -> skipBytes(2)
            15 -> skipBytes(3)
            else -> error("Unknown JVM constant-pool tag.")
        }
        index++
    }
    return readUnsignedShort()
}

private const val CLASS_FILE_MAGIC = -889275714
private const val PUBLIC_ACCESS = 0x0001
private val PRIVATE_IMPLEMENTATION_TYPES = listOf(
    "io.github.seamcarving.mlkit.FaceBoxDetector",
    "io.github.seamcarving.mlkit.FaceBoxDetectorFactory",
    "io.github.seamcarving.mlkit.FaceProtectionMask",
)
