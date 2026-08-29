package io.github.seamcarving

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.util.concurrent.ExecutionException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import org.swift.swiftkit.core.ClosableSwiftArena
import org.swift.swiftkit.core.SwiftArena

class SeamCarver {
    suspend fun resize(request: ResizeRequest): RgbaImage =
        withContext(Dispatchers.Default) {
            NativeResizeExecutor.execute(request) { _, _, _, _ -> true }
        }

    fun resizeWithProgress(request: ResizeRequest): Flow<ResizeProgress> =
        channelFlow {
            NativeResizeExecutor.execute(request) { completed, total, width, height ->
                if (!isActive) {
                    false
                } else {
                    val delivery = trySendBlocking(
                        ResizeProgress(
                            completedEdits = completed,
                            totalEdits = total,
                            width = width,
                            height = height,
                        ),
                    )
                    delivery.isSuccess && isActive
                }
            }
        }.flowOn(Dispatchers.Default)
}

private object NativeResizeExecutor {
    suspend fun execute(
        request: ResizeRequest,
        onProgress: (completed: Int, total: Int, width: Int, height: Int) -> Boolean,
    ): RgbaImage {
        try {
            val arena = SwiftArena.ofConfined()
            val operation = AndroidResizeOperation.`init`(arena)
            val future = operation.resize(
                request.image.width,
                request.image.height,
                request.image.bytes,
                request.targetWidth,
                request.targetHeight,
                request.protectionMask?.values ?: FloatArray(0),
                request.removalMask?.values ?: FloatArray(0),
                { completed, total, width, height ->
                    onProgress(completed, total, width, height)
                },
                arena,
            )
            try {
                val result = FutureAwaiter.await(future, operation::cancel)
                return RgbaImage(result.width, result.height, result.bytes)
            } finally {
                closeArenaAfterNativeCompletion(arena, future)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw SeamCarvingException("Seam carving resize failed.", error)
        }
    }

    private fun closeArenaAfterNativeCompletion(
        arena: ClosableSwiftArena,
        future: CompletableFuture<*>,
    ) {
        if (future.isDone) {
            arena.close()
        } else {
            future.whenComplete { _, _ -> arena.close() }
        }
    }
}

private object FutureAwaiter {
    suspend fun <T> await(future: CompletableFuture<T>): T = suspendCoroutine { continuation ->
        future.whenComplete { result, error ->
            if (error == null) {
                continuation.resume(result)
            } else {
                continuation.resumeWithException(error.unwrapCompletionCause())
            }
        }
    }

    suspend fun <T> await(
        future: CompletableFuture<T>,
        cancelNative: () -> Unit,
    ): T = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation {
            cancelNative()
        }
        future.whenComplete { result, error ->
            if (error == null) {
                continuation.resume(result)
            } else {
                continuation.resumeWithException(error.unwrapCompletionCause())
            }
        }
    }

    private fun Throwable.unwrapCompletionCause(): Throwable =
        when (this) {
            is CompletionException, is ExecutionException -> cause?.unwrapCompletionCause() ?: this
            else -> this
        }
}
