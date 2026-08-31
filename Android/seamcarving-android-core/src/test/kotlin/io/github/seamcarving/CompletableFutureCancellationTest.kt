package io.github.seamcarving

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.lang.reflect.InvocationTargetException
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.startCoroutine
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Test

class CompletableFutureCancellationTest {
    @Test
    fun cancellingAwaitInvokesNativeCancellationWithoutCancellingTheWrapperFuture() = runTest {
        val future = CompletableFuture<RgbaImage>()
        val nativeCancellationCount = AtomicInteger()
        val job = launch {
            invokePrivateAwait(future) {
                nativeCancellationCount.incrementAndGet()
            }
        }
        yield()

        job.cancelAndJoin()

        assertEquals(1, nativeCancellationCount.get())
        assertFalse(future.isCancelled)
    }

    @Test
    fun preservesCancellationWrappedByACompletionException() {
        val cancellation = CancellationException("cancelled")
        val future = CompletableFuture<RgbaImage>()
        future.completeExceptionally(CompletionException(cancellation))

        val thrown = try {
            runSuspend { invokePrivateAwait(future) }
            throw AssertionError("Expected cancellation")
        } catch (error: CancellationException) {
            error
        }

        assertSame(cancellation, thrown)
    }
}

private suspend fun <T> invokePrivateAwait(
    future: CompletableFuture<T>,
    cancelNative: (() -> Unit)? = null,
): T =
    suspendCoroutine { continuation ->
        val awaiter = Class.forName("io.github.seamcarving.FutureAwaiter")
        check(!java.lang.reflect.Modifier.isPublic(awaiter.modifiers)) {
            "FutureAwaiter must be a non-public JVM implementation type: $awaiter"
        }
        val instance = awaiter.getDeclaredField("INSTANCE").get(null)
        val method = awaiter.declaredMethods.singleOrNull { candidate ->
            candidate.name == "await" &&
                candidate.parameterCount == if (cancelNative == null) 2 else 3
        } ?: throw AssertionError("FutureAwaiter must own the private boundary implementation")
        method.isAccessible = true
        try {
            val result = if (cancelNative == null) {
                method.invoke(instance, future, continuation)
            } else {
                method.invoke(instance, future, cancelNative, continuation)
            }
            if (result !== COROUTINE_SUSPENDED) {
                @Suppress("UNCHECKED_CAST")
                continuation.resume(result as T)
            }
        } catch (error: InvocationTargetException) {
            continuation.resumeWithException(error.cause ?: error)
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
