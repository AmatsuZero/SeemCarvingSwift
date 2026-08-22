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
        let pixelCount = width * height

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

        // 2. Sobel via vDSP, symmetric-difference form with clamp-to-edge.
        let leftUp = shifted(luma, width: width, height: height, dx: -1, dy: -1)
        let midUp = shifted(luma, width: width, height: height, dx: 0, dy: -1)
        let rightUp = shifted(luma, width: width, height: height, dx: 1, dy: -1)
        let leftMid = shifted(luma, width: width, height: height, dx: -1, dy: 0)
        let rightMid = shifted(luma, width: width, height: height, dx: 1, dy: 0)
        let leftDown = shifted(luma, width: width, height: height, dx: -1, dy: 1)
        let midDown = shifted(luma, width: width, height: height, dx: 0, dy: 1)
        let rightDown = shifted(luma, width: width, height: height, dx: 1, dy: 1)

        var scratch = [Float](repeating: 0, count: pixelCount)
        var gx = [Float](repeating: 0, count: pixelCount)
        var gy = [Float](repeating: 0, count: pixelCount)

        // gx = (rightUp - leftUp) + 2*(rightMid - leftMid) + (rightDown - leftDown)
        vDSP.subtract(rightUp, leftUp, result: &gx)
        vDSP.subtract(rightMid, leftMid, result: &scratch)
        vDSP.add(gx, scale(scratch, by: 2), result: &gx)
        vDSP.subtract(rightDown, leftDown, result: &scratch)
        vDSP.add(gx, scratch, result: &gx)

        // gy = (leftDown - leftUp) + 2*(midDown - midUp) + (rightDown - rightUp)
        vDSP.subtract(leftDown, leftUp, result: &gy)
        vDSP.subtract(midDown, midUp, result: &scratch)
        vDSP.add(gy, scale(scratch, by: 2), result: &gy)
        vDSP.subtract(rightDown, rightUp, result: &scratch)
        vDSP.add(gy, scratch, result: &gy)

        // energy = |gx| + |gy|
        vDSP.absolute(gx, result: &gx)
        vDSP.absolute(gy, result: &gy)
        var energy = [Float](repeating: 0, count: pixelCount)
        vDSP.add(gx, gy, result: &energy)

        return try EnergyMap(width: width, height: height, values: energy)
    }

    private static func scale(_ x: [Float], by scalar: Float) -> [Float] {
        var result = [Float](repeating: 0, count: x.count)
        var s = scalar
        vDSP_vsmul(x, 1, &s, &result, 1, vDSP_Length(x.count))
        return result
    }

    private static func shifted(_ src: [Float], width: Int, height: Int, dx: Int, dy: Int) -> [Float] {
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            let sy = min(max(y + dy, 0), height - 1)
            for x in 0..<width {
                let sx = min(max(x + dx, 0), width - 1)
                out[y * width + x] = src[sy * width + sx]
            }
        }
        return out
    }
}
