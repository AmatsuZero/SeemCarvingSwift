package io.github.seamcarving

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.util.concurrent.ExecutionException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import org.swift.swiftkit.core.SwiftArena

class SeamCarver {
    suspend fun resize(request: ResizeRequest): RgbaImage {
        try {
            val arena = SwiftArena.ofConfined()
            try {
                val result = AndroidResizeBridge.resize(
                    request.image.width,
                    request.image.height,
                    request.image.bytes,
                    request.targetWidth,
                    request.targetHeight,
                    request.protectionMask?.values ?: FloatArray(0),
                    request.removalMask?.values ?: FloatArray(0),
                    arena,
                ).awaitResult()
                return RgbaImage(result.width, result.height, result.bytes)
            } finally {
                arena.close()
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw SeamCarvingException("Seam carving resize failed.", error)
        }
    }
}

internal suspend fun <T> CompletableFuture<T>.awaitResult(): T = suspendCoroutine { continuation ->
    whenComplete { result, error ->
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
