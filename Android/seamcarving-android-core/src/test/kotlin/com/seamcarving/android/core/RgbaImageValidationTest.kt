package com.seamcarving.android.core

import org.junit.Assert.assertThrows
import org.junit.Test

class RgbaImageValidationTest {
    @Test
    fun rejectsBytesThatDoNotCoverEveryRgbaPixel() {
        assertThrows(IllegalArgumentException::class.java) {
            RgbaImage(2, 2, ByteArray(15))
        }
    }

    @Test
    fun rejectsDimensionsWhoseRgbaByteCountOverflows() {
        assertThrows(ArithmeticException::class.java) {
            RgbaImage(46_341, 46_341, ByteArray(0))
        }
    }

    @Test
    fun rejectsAMaskWhoseDimensionsDifferFromTheSourceImage() {
        assertThrows(IllegalArgumentException::class.java) {
            ResizeRequest(
                image = RgbaImage(2, 2, ByteArray(16)),
                targetWidth = 1,
                targetHeight = 2,
                protectionMask = Mask(1, 2, floatArrayOf(0f, 1f)),
            )
        }
    }
}
