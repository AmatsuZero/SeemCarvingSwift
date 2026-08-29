package io.github.seamcarving.bitmap

import android.graphics.Bitmap
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BitmapConversionTest {
    @Test
    fun bitmapToRgbaImagePreservesChannelOrderAndStraightAlpha() {
        val bitmap = Bitmap.createBitmap(
            intArrayOf(0x80402010.toInt()),
            1,
            1,
            Bitmap.Config.ARGB_8888,
        )

        val image = bitmap.toRgbaImage()

        assertArrayEquals(
            byteArrayOf(0x40, 0x20, 0x10, 0x80.toByte()),
            image.bytes,
        )
    }

    @Test
    fun bitmapToRgbaImageUsesLogicalRowsInsteadOfStorageStride() {
        val colors = intArrayOf(
            0xff010203.toInt(),
            0xff111213.toInt(),
            0xff212223.toInt(),
            0xff313233.toInt(),
            0xff414243.toInt(),
            0xff515253.toInt(),
        )
        val bitmap = Bitmap.createBitmap(colors, 3, 2, Bitmap.Config.ARGB_8888)

        assertArrayEquals(
            byteArrayOf(
                0x01, 0x02, 0x03, 0xff.toByte(),
                0x11, 0x12, 0x13, 0xff.toByte(),
                0x21, 0x22, 0x23, 0xff.toByte(),
                0x31, 0x32, 0x33, 0xff.toByte(),
                0x41, 0x42, 0x43, 0xff.toByte(),
                0x51, 0x52, 0x53, 0xff.toByte(),
            ),
            bitmap.toRgbaImage().bytes,
        )
    }

    @Test
    fun bitmapToRgbaImageAcceptsImmutableArgb8888WithoutMutatingSource() {
        val mutable = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888).apply {
            setPixel(0, 0, 0x7f123456)
        }
        val bitmap = mutable.copy(Bitmap.Config.ARGB_8888, false)
        val original = bitmap.getPixel(0, 0)

        val image = bitmap.toRgbaImage()
        image.bytes.fill(0)

        assertFalse(bitmap.isMutable)
        assertEquals(original, bitmap.getPixel(0, 0))
    }

    @Test
    fun bitmapToRgbaImageRejectsNonArgb8888Config() {
        val bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.RGB_565)

        assertThrows(IllegalArgumentException::class.java) {
            bitmap.toRgbaImage()
        }
    }

    @Test
    fun rgbaImageToBitmapReturnsNewMutableCallerOwnedBitmap() {
        val bytes = byteArrayOf(
            0x40, 0x20, 0x10, 0x80.toByte(),
            0xaa.toByte(), 0xbb.toByte(), 0xcc.toByte(), 0xff.toByte(),
        )
        val image = io.github.seamcarving.RgbaImage(2, 1, bytes)

        val bitmap = image.toBitmap()
        bytes.fill(0)

        assertEquals(Bitmap.Config.ARGB_8888, bitmap.config)
        assertTrue(bitmap.isMutable)
        assertTrue(bitmap.hasAlpha())
        assertEquals(0x80402010.toInt(), bitmap.getPixel(0, 0))
        assertEquals(0xffaabbcc.toInt(), bitmap.getPixel(1, 0))
    }

    @Test
    fun seamCarveToReturnsNewBitmapAndLeavesSourceOwnedByCaller() = runBlocking {
        val source = twoByTwoFixture()

        val result = source.seamCarveTo(width = 1, height = 2)

        assertNotSame(source, result)
        assertFalse(source.isRecycled)
        assertEquals(2, source.width)
        assertEquals(2, source.height)
        assertEquals(1, result.width)
        assertEquals(2, result.height)
        assertTrue(result.isMutable)
    }

    @Test
    fun cancellingBitmapProgressCollectionStopsFurtherDelivery() = runBlocking {
        val deliveryCount = AtomicInteger()
        val source = gradientBitmap(width = 96, height = 64)
        val job = launch {
            source.seamCarveToWithProgress(width = 1, height = 64).collect {
                deliveryCount.incrementAndGet()
                cancel()
            }
        }

        withTimeout(30_000) { job.join() }
        assertTrue(job.isCancelled)
        assertEquals(1, deliveryCount.get())

        delay(200)
        assertEquals(1, deliveryCount.get())
        assertFalse(source.isRecycled)
    }

    private fun twoByTwoFixture(): Bitmap = Bitmap.createBitmap(
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

    private fun gradientBitmap(width: Int, height: Int): Bitmap {
        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val value = (x * 61 + y * 37) % 256
                pixels[y * width + x] =
                    (0xff shl 24) or (value shl 16) or (value shl 8) or value
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
