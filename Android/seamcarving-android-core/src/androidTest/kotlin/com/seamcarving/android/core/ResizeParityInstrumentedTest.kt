package com.seamcarving.android.core

import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import java.util.concurrent.CountDownLatch
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ResizeParityInstrumentedTest {
    @Test
    fun twoByTwoFixtureMatchesTheCanonicalCoreResult() {
        val result = runSuspend {
            SeamCarver().resize(
                ResizeRequest(
                    image = RgbaImage(
                        2,
                        2,
                        byteArrayOf(
                            0, 0, 0, -1,
                            -1, 0, 0, -1,
                            0, -1, 0, -1,
                            0, 0, -1, -1,
                        ),
                    ),
                    targetWidth = 1,
                    targetHeight = 2,
                ),
            )
        }

        assertEquals(1, result.width)
        assertEquals(2, result.height)
        assertArrayEquals(
            byteArrayOf(
                0, 0, 0, -1,
                0, -1, 0, -1,
            ),
            result.bytes,
        )
    }
}

private fun <T> runSuspend(block: suspend () -> T): T {
    var outcome: Result<T>? = null
    val completed = CountDownLatch(1)
    block.startCoroutine(object : Continuation<T> {
        override val context = EmptyCoroutineContext

        override fun resumeWith(result: Result<T>) {
            outcome = result
            completed.countDown()
        }
    })
    try {
        completed.await()
    } catch (error: InterruptedException) {
        Thread.currentThread().interrupt()
        throw AssertionError("Interrupted while awaiting seam-carving resize.", error)
    }
    return checkNotNull(outcome).getOrThrow()
}
