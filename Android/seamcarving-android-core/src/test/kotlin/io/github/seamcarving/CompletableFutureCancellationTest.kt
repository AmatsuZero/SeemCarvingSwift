package io.github.seamcarving

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import org.junit.Assert.assertSame
import org.junit.Test

class CompletableFutureCancellationTest {
    @Test
    fun preservesCancellationWrappedByACompletionException() {
        val cancellation = CancellationException("cancelled")
        val future = CompletableFuture<RgbaImage>()
        future.completeExceptionally(CompletionException(cancellation))

        val thrown = try {
            runSuspend { future.awaitResult() }
            throw AssertionError("Expected cancellation")
        } catch (error: CancellationException) {
            error
        }

        assertSame(cancellation, thrown)
    }
}

private fun <T> runSuspend(block: suspend () -> T): T {
    var outcome: Result<T>? = null
    block.startCoroutine(object : Continuation<T> {
        override val context = EmptyCoroutineContext

        override fun resumeWith(result: Result<T>) {
            outcome = result
        }
    })
    return checkNotNull(outcome).getOrThrow()
}
