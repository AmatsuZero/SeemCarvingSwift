package io.github.seamcarving.mlkit

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MlKitFaceDetectorTest {
    @Test
    fun faceBoxFixtureIsRasterizedThroughBitmapApi() = runBlocking {
        val bitmap = Bitmap.createBitmap(8, 6, Bitmap.Config.ARGB_8888)

        val mask = bitmap.detectFaceProtectionMask(
            detect = { listOf(Rect(2, 1, 6, 5)) },
            close = {},
        )

        assertEquals(0f, mask.values[0])
        assertEquals(1f, mask.values[3 * mask.width + 3])
    }

    @Test
    fun bundledMlKitDetectorReturnsZeroMaskForBlankFixture() = runBlocking {
        val bitmap = Bitmap.createBitmap(480, 360, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.WHITE)
        }

        val mask = withTimeout(30_000) {
            bitmap.detectFaceProtectionMask()
        }

        assertEquals(bitmap.width, mask.width)
        assertEquals(bitmap.height, mask.height)
        assertTrue(mask.values.all { it == 0f })
    }
}
