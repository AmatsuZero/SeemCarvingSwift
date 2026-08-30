package io.github.seamcarving.mlkit

import android.graphics.Bitmap
import android.graphics.Rect
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.github.seamcarving.Mask
import io.github.seamcarving.SeamCarvingException
import java.util.concurrent.Executor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

/**
 * Detects faces in this caller-owned [Bitmap] and returns a protection mask
 * with the same dimensions.
 *
 * Detection is implemented entirely by this optional Android artifact. The
 * Bitmap is not mutated or recycled, and no ML Kit type crosses the public
 * API boundary. Cancelling the coroutine stops waiting for the detector and
 * releases its client; detector failures are exposed as
 * [SeamCarvingException] while retaining the original exception as the cause.
 */
suspend fun Bitmap.detectFaceProtectionMask(): Mask =
    detectFaceProtectionMaskInternal(::createMlKitDetector)

@JvmSynthetic
internal suspend fun Bitmap.detectFaceProtectionMask(
    detect: suspend (Bitmap) -> List<Rect>,
    close: () -> Unit,
    paddingPixels: Int = 0,
): Mask {
    val detectFaces = detect
    val closeDetector = close
    return detectFaceProtectionMaskInternal(
        detectorFactory = {
            Pair(detectFaces, closeDetector)
        },
        paddingPixels = paddingPixels,
    )
}

private suspend fun Bitmap.detectFaceProtectionMaskInternal(
    detectorFactory: () -> Pair<suspend (Bitmap) -> List<Rect>, () -> Unit>,
    paddingPixels: Int = 0,
): Mask {
    require(!isRecycled) { "Cannot detect faces in a recycled Bitmap." }
    require(paddingPixels >= 0) { "Face-mask padding must not be negative." }

    currentCoroutineContext().ensureActive()
    val (detect, close) = try {
        detectorFactory()
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        throw SeamCarvingException("Unable to create the ML Kit face detector.", error)
    }

    try {
        val rectangles = try {
            detect(this)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw SeamCarvingException("ML Kit face detection failed.", error)
        }
        currentCoroutineContext().ensureActive()
        return withContext(Dispatchers.Default) {
            FaceProtectionMask.rasterize(width, height, rectangles, paddingPixels)
        }
    } finally {
        close()
    }
}

@JvmSynthetic
internal fun rasterizeFaceProtectionMask(
    width: Int,
    height: Int,
    faceRectangles: List<Rect>,
    paddingPixels: Int = 0,
): Mask = FaceProtectionMask.rasterize(width, height, faceRectangles, paddingPixels)

private object FaceProtectionMask {
    fun rasterize(
        width: Int,
        height: Int,
        faceRectangles: List<Rect>,
        paddingPixels: Int = 0,
    ): Mask {
        require(width > 0 && height > 0) { "Mask dimensions must be positive." }
        require(paddingPixels >= 0) { "Face-mask padding must not be negative." }

        val values = FloatArray(Math.multiplyExact(width, height))
        val maximumX = width.toLong()
        val maximumY = height.toLong()
        val padding = paddingPixels.toLong()

        faceRectangles.forEach { rectangle ->
            val left = (rectangle.left.toLong() - padding)
                .coerceIn(0L, maximumX)
                .toInt()
            val top = (rectangle.top.toLong() - padding)
                .coerceIn(0L, maximumY)
                .toInt()
            val right = (rectangle.right.toLong() + padding)
                .coerceIn(0L, maximumX)
                .toInt()
            val bottom = (rectangle.bottom.toLong() + padding)
                .coerceIn(0L, maximumY)
                .toInt()

            for (y in top until bottom) {
                val rowOffset = y * width
                for (x in left until right) {
                    values[rowOffset + x] = PROTECTION_VALUE
                }
            }
        }

        return Mask(width, height, values)
    }
}

private fun createMlKitDetector(): Pair<suspend (Bitmap) -> List<Rect>, () -> Unit> {
    val options = FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
        .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
        .build()
    val detector = FaceDetection.getClient(options)
    val detect: suspend (Bitmap) -> List<Rect> = { bitmap ->
        detector.process(InputImage.fromBitmap(bitmap, NO_ROTATION_DEGREES))
            .awaitCancellable()
            .map { face -> Rect(face.boundingBox) }
    }
    return Pair(detect, detector::close)
}

private suspend fun <T> Task<T>.awaitCancellable(): T =
    suspendCancellableCoroutine { continuation ->
        addOnCompleteListener(DIRECT_EXECUTOR) { completed ->
            if (!continuation.isActive) return@addOnCompleteListener
            when {
                completed.isCanceled -> continuation.cancel()
                completed.isSuccessful -> continuation.resumeWith(Result.success(completed.result))
                else -> continuation.resumeWith(
                    Result.failure(
                        completed.exception
                            ?: IllegalStateException("ML Kit task failed without an exception."),
                    ),
                )
            }
        }
    }

private val DIRECT_EXECUTOR = Executor { command -> command.run() }
private const val NO_ROTATION_DEGREES = 0
private const val PROTECTION_VALUE = 1f
