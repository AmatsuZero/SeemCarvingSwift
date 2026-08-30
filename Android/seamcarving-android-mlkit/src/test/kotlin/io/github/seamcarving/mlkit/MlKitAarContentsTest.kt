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
    fun releaseAarPublicAbiDoesNotReferenceGoogleOrNonPublicImplementationTypes() {
        val releaseAar = File(checkNotNull(System.getProperty("releaseAar")))
        val classesJar = Files.createTempFile("seamcarving-mlkit-release", ".jar").toFile()
        ZipFile(releaseAar).use { archive ->
            val entry = checkNotNull(archive.getEntry("classes.jar"))
            archive.getInputStream(entry).use { input ->
                classesJar.outputStream().use(input::transferTo)
            }
        }

        val (publicClasses, nonPublicClasses) = classesJar.classNamesByVisibility()
        val leakingMethods = publicClasses.flatMap { className ->
            javapPrivate(classesJar, className).lineSequence()
                .map(String::trim)
                .filter { line ->
                    line.startsWith("public ") && line.contains('(') &&
                        (
                            GOOGLE_IMPLEMENTATION_PREFIXES.any(line::contains) ||
                                nonPublicClasses.any(line::contains)
                        )
                }
                .map { signature -> "$className: $signature" }
                .toList()
        }
        assertTrue(
            "Release AAR public ABI references Google or non-public implementation types: " +
                leakingMethods.joinToString(),
            leakingMethods.isEmpty(),
        )
    }
}

private fun File.classNamesByVisibility(): Pair<List<String>, List<String>> {
    val publicClasses = mutableListOf<String>()
    val nonPublicClasses = mutableListOf<String>()
    JarInputStream(inputStream()).use { jar ->
        while (true) {
            val entry = jar.nextJarEntry ?: break
            if (!entry.name.endsWith(".class")) continue
            val className = entry.name.removeSuffix(".class").replace('/', '.')
            val accessFlags = DataInputStream(jar).readClassAccessFlags()
            if (accessFlags and PUBLIC_ACCESS != 0) {
                publicClasses += className
            } else {
                nonPublicClasses += className
            }
        }
    }
    return publicClasses to nonPublicClasses
}

private fun javapPrivate(classesJar: File, className: String): String {
    val javap = File(System.getProperty("java.home"), "bin/javap")
    assertTrue("Release API test requires javap at $javap", javap.canExecute())
    val process = ProcessBuilder(
        javap.absolutePath,
        "-private",
        "-classpath",
        classesJar.toString(),
        className,
    ).redirectErrorStream(true).start()
    val output = process.inputStream.bufferedReader().readText()
    assertEquals("javap failed for $className:\n$output", 0, process.waitFor())
    return output
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
private val GOOGLE_IMPLEMENTATION_PREFIXES = listOf(
    "com.google.android.gms.",
    "com.google.mlkit.",
)
