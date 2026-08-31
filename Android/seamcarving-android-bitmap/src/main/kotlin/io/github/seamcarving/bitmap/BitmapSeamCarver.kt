package io.github.seamcarving.bitmap

import android.graphics.Bitmap
import io.github.seamcarving.Mask
import io.github.seamcarving.ResizeProgress
import io.github.seamcarving.ResizeRequest
import io.github.seamcarving.RgbaImage
import io.github.seamcarving.SeamCarver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext

/**
 * Copies this caller-owned [Bitmap] into an upright, row-major RGBA8 image.
 *
 * The source is neither mutated nor recycled. Only [Bitmap.Config.ARGB_8888]
 * is accepted so conversion never silently discards alpha or color precision.
 * Android's packed-color API is used instead of raw storage, which makes the
 * conversion independent of both native byte order and [Bitmap.rowBytes]
 * padding.
 */
fun Bitmap.toRgbaImage(): RgbaImage {
    require(!isRecycled) { "Cannot read a recycled Bitmap." }
    require(config == Bitmap.Config.ARGB_8888) {
        "Bitmap config must be ARGB_8888 but was $config."
    }

    val pixelCount = Math.multiplyExact(width, height)
    val packedPixels = IntArray(pixelCount)
    getPixels(packedPixels, 0, width, 0, 0, width, height)

    val rgba = ByteArray(Math.multiplyExact(pixelCount, RGBA_CHANNEL_COUNT))
    packedPixels.forEachIndexed { index, pixel ->
        val byteOffset = index * RGBA_CHANNEL_COUNT
        rgba[byteOffset] = (pixel ushr 16).toByte()
        rgba[byteOffset + 1] = (pixel ushr 8).toByte()
        rgba[byteOffset + 2] = pixel.toByte()
        rgba[byteOffset + 3] = (pixel ushr 24).toByte()
    }
    return RgbaImage(width, height, rgba)
}

/**
 * Copies this RGBA8 image into a new mutable, caller-owned ARGB_8888 bitmap.
 * Mutating or recycling the result never affects this image's byte array.
 */
fun RgbaImage.toBitmap(): Bitmap {
    val pixelCount = Math.multiplyExact(width, height)
    val packedPixels = IntArray(pixelCount)
    for (index in 0 until pixelCount) {
        val byteOffset = index * RGBA_CHANNEL_COUNT
        val red = bytes[byteOffset].toInt() and 0xff
        val green = bytes[byteOffset + 1].toInt() and 0xff
        val blue = bytes[byteOffset + 2].toInt() and 0xff
        val alpha = bytes[byteOffset + 3].toInt() and 0xff
        packedPixels[index] =
            (alpha shl 24) or (red shl 16) or (green shl 8) or blue
    }

    return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
        setHasAlpha(true)
        setPixels(packedPixels, 0, width, 0, 0, width, height)
    }
}

/**
 * Seam-carves a snapshot of this bitmap off the caller's thread and returns a
 * new mutable bitmap. The source remains owned by the caller and is untouched.
 */
suspend fun Bitmap.seamCarveTo(
    width: Int,
    height: Int,
    protectionMask: Mask? = null,
    removalMask: Mask? = null,
): Bitmap = withContext(Dispatchers.Default) {
    val request = toResizeRequest(width, height, protectionMask, removalMask)
    SeamCarver().resize(request).toBitmap()
}

/**
 * Runs the same bitmap-backed resize while exposing Core progress updates.
 * Cancelling collection is forwarded to the native resize operation. The
 * source remains caller-owned; this progress-only surface does not allocate a
 * result bitmap.
 */
fun Bitmap.seamCarveToWithProgress(
    width: Int,
    height: Int,
    protectionMask: Mask? = null,
    removalMask: Mask? = null,
): Flow<ResizeProgress> = flow {
    val request = toResizeRequest(width, height, protectionMask, removalMask)
    emitAll(SeamCarver().resizeWithProgress(request))
}.flowOn(Dispatchers.Default)

private fun Bitmap.toResizeRequest(
    width: Int,
    height: Int,
    protectionMask: Mask?,
    removalMask: Mask?,
): ResizeRequest = ResizeRequest(
    image = toRgbaImage(),
    targetWidth = width,
    targetHeight = height,
    protectionMask = protectionMask,
    removalMask = removalMask,
)

private const val RGBA_CHANNEL_COUNT = 4
