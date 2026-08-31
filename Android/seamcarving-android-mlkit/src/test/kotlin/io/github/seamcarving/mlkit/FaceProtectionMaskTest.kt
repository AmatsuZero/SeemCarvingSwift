package io.github.seamcarving.mlkit

import android.graphics.Bitmap
import android.graphics.Rect
import io.github.seamcarving.SeamCarvingException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class FaceProtectionMaskTest {
    @Test
    fun faceRectangleCreatesBoundedProtection() {
        val mask = rasterizeFaceProtectionMask(
            width = 8,
            height = 6,
            faceRectangles = listOf(Rect(2, 1, 6, 5)),
        )

        assertEquals(0f, mask.valueAt(0, 0))
        assertEquals(1f, mask.valueAt(3, 3))
        assertEquals(0f, mask.valueAt(6, 3))
        assertEquals(0f, mask.valueAt(3, 5))
    }

    @Test
    fun rectangleOutsideImageIsClampedToMaskBounds() {
        val mask = rasterizeFaceProtectionMask(
            width = 4,
            height = 3,
            faceRectangles = listOf(Rect(-2, -1, 3, 2)),
        )

        assertEquals(1f, mask.valueAt(0, 0))
        assertEquals(1f, mask.valueAt(2, 1))
        assertEquals(0f, mask.valueAt(3, 1))
        assertEquals(0f, mask.valueAt(0, 2))
    }

    @Test
    fun paddingExpandsRectangleAndStillClampsAtImageEdge() {
        val mask = rasterizeFaceProtectionMask(
            width = 5,
            height = 4,
            faceRectangles = listOf(Rect(0, 1, 2, 3)),
            paddingPixels = 1,
        )

        assertEquals(1f, mask.valueAt(0, 0))
        assertEquals(1f, mask.valueAt(2, 3))
        assertEquals(0f, mask.valueAt(3, 3))
    }

    @Test
    fun emptyFaceListCreatesAllZeroMask() {
        val mask = rasterizeFaceProtectionMask(3, 2, emptyList())

        assertTrue(mask.values.all { it == 0f })
    }

    @Test
    fun negativePaddingIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            rasterizeFaceProtectionMask(
                width = 2,
                height = 2,
                faceRectangles = emptyList(),
                paddingPixels = -1,
            )
        }
    }

    @Test
    fun bitmapDetectorFaceBoxesFlowThroughTheBitmapPath() = runBlocking {
        val detector = RecordingDetector(result = listOf(Rect(1, 1, 3, 3)))
        val bitmap = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)

        val mask = bitmap.detectFaceProtectionMask(
            detect = detector::detect,
            close = detector::close,
        )

        assertSame(bitmap, detector.receivedBitmap)
        assertEquals(1f, mask.valueAt(1, 1))
        assertEquals(0f, mask.valueAt(3, 3))
        assertTrue(detector.closed.get())
    }

    @Test
    fun detectorFailureKeepsOriginalCauseAndClosesDetector() {
        val cause = IllegalStateException("detector failed")
        val detector = RecordingDetector(failure = cause)
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)

        val thrown = assertThrows(SeamCarvingException::class.java) {
            runBlocking {
                bitmap.detectFaceProtectionMask(
                    detect = detector::detect,
                    close = detector::close,
                )
            }
        }

        assertSame(cause, thrown.cause)
        assertTrue(detector.closed.get())
    }

    @Test
    fun cancellationIsNotWrappedAndClosesDetector() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val detector = RecordingDetector(started = started, suspendForever = true)
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)

        val job = launch {
            bitmap.detectFaceProtectionMask(
                detect = detector::detect,
                close = detector::close,
            )
        }
        started.await()
        job.cancelAndJoin()

        assertTrue(job.isCancelled)
        assertTrue(detector.closed.get())
    }

    @Test
    fun detectorFailureRemainsPrimaryWhenClosingDetectorAlsoFails() {
        val detectionFailure = IllegalStateException("detector failed")
        val closeFailure = IllegalStateException("close failed")
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)

        val thrown = assertThrows(SeamCarvingException::class.java) {
            runBlocking {
                bitmap.detectFaceProtectionMask(
                    detect = { throw detectionFailure },
                    close = { throw closeFailure },
                )
            }
        }

        assertSame(detectionFailure, thrown.cause)
        assertEquals(listOf(closeFailure), thrown.suppressed.toList())
    }

    @Test
    fun cancellationRemainsPrimaryWhenClosingDetectorAlsoFails() {
        val cancellation = CancellationException("cancelled")
        val closeFailure = IllegalStateException("close failed")
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)

        val thrown = assertThrows(CancellationException::class.java) {
            runBlocking {
                bitmap.detectFaceProtectionMask(
                    detect = { throw cancellation },
                    close = { throw closeFailure },
                )
            }
        }

        assertSame(cancellation, thrown)
        assertEquals(listOf(closeFailure), thrown.suppressed.toList())
    }

    private class RecordingDetector(
        private val result: List<Rect> = emptyList(),
        private val failure: Throwable? = null,
        private val started: CompletableDeferred<Unit>? = null,
        private val suspendForever: Boolean = false,
    ) {
        var receivedBitmap: Bitmap? = null
        val closed = AtomicBoolean()

        suspend fun detect(bitmap: Bitmap): List<Rect> {
            receivedBitmap = bitmap
            started?.complete(Unit)
            if (suspendForever) awaitCancellation()
            failure?.let { throw it }
            return result
        }

        fun close() {
            closed.set(true)
        }
    }
}

private fun io.github.seamcarving.Mask.valueAt(x: Int, y: Int): Float =
    values[y * width + x]
