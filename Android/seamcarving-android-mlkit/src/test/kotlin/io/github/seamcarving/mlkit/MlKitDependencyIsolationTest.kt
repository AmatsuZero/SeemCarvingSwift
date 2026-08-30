package io.github.seamcarving.mlkit

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MlKitDependencyIsolationTest {
    @Test
    fun onlyOptionalMlKitRuntimeContainsFaceDetection() {
        val coreRuntime = coordinates("coreRuntimeCoordinates")
        val bitmapRuntime = coordinates("bitmapRuntimeCoordinates")
        val mlKitRuntime = coordinates("mlKitRuntimeCoordinates")

        assertFalse(coreRuntime.any(::isMlKitCoordinate))
        assertFalse(bitmapRuntime.any(::isMlKitCoordinate))
        assertTrue(
            "Expected bundled ML Kit face detection only in the optional runtime: $mlKitRuntime",
            "com.google.mlkit:face-detection:16.1.7" in mlKitRuntime,
        )
    }

    private fun coordinates(propertyName: String): Set<String> =
        checkNotNull(System.getProperty(propertyName)) {
            "Gradle must provide $propertyName from the resolved runtime graph."
        }.lineSequence().filter(String::isNotBlank).toSet()

    private fun isMlKitCoordinate(coordinate: String): Boolean =
        coordinate.startsWith("com.google.mlkit:") ||
            coordinate.substringAfter(':').startsWith("play-services-mlkit-")
}
