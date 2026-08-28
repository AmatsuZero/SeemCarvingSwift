package io.github.seamcarving

data class Mask(val width: Int, val height: Int, val values: FloatArray) {
    init {
        require(width > 0 && height > 0) { "Mask dimensions must be positive." }
        val expectedValueCount = Math.multiplyExact(width, height)
        require(values.size == expectedValueCount) {
            "Expected $expectedValueCount mask values but received ${values.size}."
        }
        require(values.all { it.isFinite() && it in 0f..1f }) {
            "Mask values must be finite and within 0.0 through 1.0."
        }
    }
}
