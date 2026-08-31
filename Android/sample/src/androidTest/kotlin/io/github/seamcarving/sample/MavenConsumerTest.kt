package io.github.seamcarving.sample

import android.graphics.Bitmap
import io.github.seamcarving.RgbaImage
import io.github.seamcarving.bitmap.seamCarveTo
import io.github.seamcarving.bitmap.toRgbaImage
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class MavenConsumerTest {
    @Test
    fun facadeCoordinateExercisesCoreThroughBitmap() = runBlocking {
        val bitmap = Bitmap.createBitmap(
            intArrayOf(
                0xff000000.toInt(),
                0xffff0000.toInt(),
                0xff00ff00.toInt(),
                0xff0000ff.toInt(),
            ),
            2,
            2,
            Bitmap.Config.ARGB_8888,
        )

        val rgba: RgbaImage = bitmap.toRgbaImage()
        assertEquals(2, rgba.width)
        assertEquals(2, rgba.height)
        assertArrayEquals(byteArrayOf(0, 0, 0, 0xff.toByte()), rgba.bytes.copyOfRange(0, 4))

        val resized = bitmap.seamCarveTo(width = 1, height = 2)
        assertEquals(1, resized.width)
        assertEquals(2, resized.height)
    }

    @Test
    fun defaultFacadeDoesNotInstallMlKit() {
        try {
            Class.forName("com.google.mlkit.vision.face.FaceDetection")
            fail("The default facade must not pull the optional ML Kit implementation")
        } catch (_: ClassNotFoundException) {
            // Expected: ML Kit is available only through its explicit coordinate.
        }
    }
}
