package io.github.seamcarving

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CancellationAndProgressTest {
    @Test
    fun progressReportsEveryCompletedEditAndCurrentSize() = runBlocking {
        val progress = SeamCarver().resizeWithProgress(
            ResizeRequest(
                image = gradientImage(width = 4, height = 3),
                targetWidth = 2,
                targetHeight = 2,
            ),
        ).toList()

        assertEquals(listOf(1, 2, 3), progress.map(ResizeProgress::completedEdits))
        assertEquals(listOf(3, 3, 3), progress.map(ResizeProgress::totalEdits))
        assertEquals(
            listOf(3 to 3, 2 to 3, 2 to 2),
            progress.map { it.width to it.height },
        )
    }

    @Test
    fun cancellingCollectionCancelsResizeWithoutFurtherDelivery() = runBlocking {
        val deliveryCount = AtomicInteger()
        val job = launch {
            SeamCarver().resizeWithProgress(
                ResizeRequest(
                    image = gradientImage(width = 96, height = 64),
                    targetWidth = 1,
                    targetHeight = 64,
                ),
            ).collect {
                deliveryCount.incrementAndGet()
                cancel()
            }
        }

        withTimeout(30_000) { job.join() }
        assertTrue(job.isCancelled)
        assertEquals(1, deliveryCount.get())

        delay(200)
        assertEquals(1, deliveryCount.get())
    }
}

private fun gradientImage(width: Int, height: Int): RgbaImage {
    val bytes = ByteArray(width * height * 4)
    for (y in 0 until height) {
        for (x in 0 until width) {
            val value = ((x * 61 + y * 37) % 256).toByte()
            val offset = (y * width + x) * 4
            bytes[offset] = value
            bytes[offset + 1] = value
            bytes[offset + 2] = value
            bytes[offset + 3] = -1
        }
    }
    return RgbaImage(width, height, bytes)
}
