import Accelerate
import Foundation
@_spi(Backend) import SeamCarvingCore

/// Accelerate-backed backward Sobel energy, bit-compatible with the core oracle.
enum AccelerateEnergy {
    /// Must match `LinearSRGB.table` in `SeamCarvingCore` exactly (identical formula).
    private static let linearSRGB: [Float] = (0...255).map { byte -> Float in
        let c = Float(byte) / 255
        if c <= 0.04045 {
            return c / 12.92
        }
        return pow((c + 0.055) / 1.055, 2.4)
    }

    static func compute(for image: RGBA8Image) throws -> EnergyMap {
        let width = image.width
        let height = image.height
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { throw SeamCarvingError.invalidDimensions }

        // 1. Linear-light luma via the sRGB LUT and a vDSP linear combination.
        var lr = [Float](repeating: 0, count: pixelCount)
        var lg = [Float](repeating: 0, count: pixelCount)
        var lb = [Float](repeating: 0, count: pixelCount)
        image.pixels.withUnsafeBufferPointer { buffer in
            for i in 0..<pixelCount {
                let base = i * 4
                lr[i] = linearSRGB[Int(buffer[base])]
                lg[i] = linearSRGB[Int(buffer[base + 1])]
                lb[i] = linearSRGB[Int(buffer[base + 2])]
            }
        }

        var luma = scale(lr, by: 0.2126)
        vDSP.add(luma, scale(lg, by: 0.7152), result: &luma)
        vDSP.add(luma, scale(lb, by: 0.0722), result: &luma)

        var energy = [Float](repeating: 0, count: pixelCount)
        // Directly sample the eight neighbors with clamp-to-edge semantics.
        // This keeps only luma and energy resident instead of allocating eight
        // additional full-frame shifted planes.
        for y in 0..<height {
            let yUp = max(y - 1, 0)
            let yDown = min(y + 1, height - 1)
            for x in 0..<width {
                let xLeft = max(x - 1, 0)
                let xRight = min(x + 1, width - 1)

                let leftUp = luma[yUp * width + xLeft]
                let rightUp = luma[yUp * width + xRight]
                let leftMid = luma[y * width + xLeft]
                let rightMid = luma[y * width + xRight]
                let leftDown = luma[yDown * width + xLeft]
                let rightDown = luma[yDown * width + xRight]
                let midUp = luma[yUp * width + x]
                let midDown = luma[yDown * width + x]

                let gx = (rightUp - leftUp) + 2.0 * (rightMid - leftMid) + (rightDown - leftDown)
                let gy = (leftDown - leftUp) + 2.0 * (midDown - midUp) + (rightDown - rightUp)
                energy[y * width + x] = abs(gx) + abs(gy)
            }
        }

        return try EnergyMap(width: width, height: height, values: energy)
    }

    private static func scale(_ x: [Float], by scalar: Float) -> [Float] {
        var result = [Float](repeating: 0, count: x.count)
        var s = scalar
        vDSP_vsmul(x, 1, &s, &result, 1, vDSP_Length(x.count))
        return result
    }

}
