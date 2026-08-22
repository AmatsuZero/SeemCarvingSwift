public enum BackwardEnergy {
    /// Computes a backward Sobel energy map over the linear-luma plane, using
    /// clamp-to-edge sampling and the `abs(gx) + abs(gy)` gradient norm.
    public static func compute(for image: RGBA8Image) throws -> EnergyMap {
        let width = image.width
        let height = image.height
        let pixelCount = width * height

        var luma = [Float](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let base = i * 4
            luma[i] = linearLuma(
                r: image.pixels[base],
                g: image.pixels[base + 1],
                b: image.pixels[base + 2]
            )
        }

        func sample(_ x: Int, _ y: Int) -> Float {
            let sx = min(max(x, 0), width - 1)
            let sy = min(max(y, 0), height - 1)
            return luma[sy * width + sx]
        }

        var values = [Float](repeating: 0, count: pixelCount)
        for y in 0..<height {
            for x in 0..<width {
                // Symmetric-difference form of the 3×3 Sobel kernels, so constant
                // regions cancel exactly rather than accumulating rounding error.
                let gx = (sample(x + 1, y - 1) - sample(x - 1, y - 1))
                    + 2 * (sample(x + 1, y) - sample(x - 1, y))
                    + (sample(x + 1, y + 1) - sample(x - 1, y + 1))
                let gy = (sample(x - 1, y + 1) - sample(x - 1, y - 1))
                    + 2 * (sample(x, y + 1) - sample(x, y - 1))
                    + (sample(x + 1, y + 1) - sample(x + 1, y - 1))
                values[y * width + x] = abs(gx) + abs(gy)
            }
        }

        return try EnergyMap(width: width, height: height, values: values)
    }
}
