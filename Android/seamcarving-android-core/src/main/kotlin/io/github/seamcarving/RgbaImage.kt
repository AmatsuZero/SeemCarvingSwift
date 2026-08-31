package io.github.seamcarving

data class RgbaImage(val width: Int, val height: Int, val bytes: ByteArray) {
    init {
        require(width > 0 && height > 0) { "Image dimensions must be positive." }
        val expectedByteCount = Math.multiplyExact(Math.multiplyExact(width, height), 4)
        require(bytes.size == expectedByteCount) {
            "Expected $expectedByteCount RGBA bytes but received ${bytes.size}."
        }
    }
}
