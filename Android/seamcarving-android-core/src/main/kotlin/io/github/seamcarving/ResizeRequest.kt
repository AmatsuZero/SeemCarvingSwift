package io.github.seamcarving

data class ResizeRequest(
    val image: RgbaImage,
    val targetWidth: Int,
    val targetHeight: Int,
    val protectionMask: Mask? = null,
    val removalMask: Mask? = null,
) {
    init {
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive." }
        listOfNotNull(protectionMask, removalMask).forEach { mask ->
            require(mask.width == image.width && mask.height == image.height) {
                "Mask dimensions must match the source image."
            }
        }
    }
}
