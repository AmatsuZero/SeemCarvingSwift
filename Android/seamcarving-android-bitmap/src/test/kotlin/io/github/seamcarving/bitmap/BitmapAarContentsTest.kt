package io.github.seamcarving.bitmap

import java.io.File
import java.util.zip.ZipFile
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BitmapAarContentsTest {
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
}
