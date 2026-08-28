package com.seamcarving.android.core

import io.github.seamcarving.internal.AndroidResizeBridge
import java.util.concurrent.CompletableFuture
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
        } catch (error: Throwable) {
            throw SeamCarvingException("Seam carving resize failed.", error)
        }
    }
}

private suspend fun <T> CompletableFuture<T>.awaitResult(): T = suspendCoroutine { continuation ->
    whenComplete { result, error ->
        if (error == null) {
            continuation.resume(result)
        } else {
            continuation.resumeWithException(error)
        }
    }
}
