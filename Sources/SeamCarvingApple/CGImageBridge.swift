import CoreGraphics
import Foundation
import ImageIO
import SeamCarvingCore

public enum CGImageBridge {
    /// Decodes a `CGImage` into upright, origin-zero, sRGB-encoded straight-alpha RGBA8.
    public static func decode(_ image: CGImage) throws -> RGBA8Image {
        try decode(image, orientation: .up)
    }

    /// Decodes a `CGImage` and applies the given EXIF orientation to produce an upright image.
    public static func decode(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> RGBA8Image {
        guard image.bitsPerComponent <= 8 else {
            throw SeamCarvingError.unsupportedDynamicRange
        }
        if let space = image.colorSpace, isExtendedRange(space) {
            throw SeamCarvingError.unsupportedDynamicRange
        }

        let rawWidth = image.width
        let rawHeight = image.height

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        guard let context = CGContext(
            data: nil,
            width: rawWidth,
            height: rawHeight,
            bitsPerComponent: 8,
            bytesPerRow: rawWidth * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }

        // CoreGraphics bitmap contexts store rows top-down, so the buffer reads
        // directly in row-major top-left order.
        context.draw(image, in: CGRect(x: 0, y: 0, width: rawWidth, height: rawHeight))

        guard let buffer = context.data?.bindMemory(to: UInt8.self, capacity: rawWidth * rawHeight * 4) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }

        // Unpremultiply into straight alpha, defining RGB as zero when alpha is zero.
        var raw = [UInt8](repeating: 0, count: rawWidth * rawHeight * 4)
        for i in 0..<(rawWidth * rawHeight) {
            let base = i * 4
            let r = buffer[base]
            let g = buffer[base + 1]
            let b = buffer[base + 2]
            let a = buffer[base + 3]
            if a == 0 {
                raw[base] = 0
                raw[base + 1] = 0
                raw[base + 2] = 0
                raw[base + 3] = 0
            } else {
                raw[base] = unpremultiply(r, alpha: a)
                raw[base + 1] = unpremultiply(g, alpha: a)
                raw[base + 2] = unpremultiply(b, alpha: a)
                raw[base + 3] = a
            }
        }

        // Apply the EXIF orientation permutation.
        let rawImage = try RGBA8Image(width: rawWidth, height: rawHeight, pixels: raw)
        return try applyOrientation(orientation, to: rawImage)
    }

    /// Applies an EXIF orientation to an upright top-left-origin RGBA8 image.
    static func applyOrientation(_ orientation: CGImagePropertyOrientation, to image: RGBA8Image) throws -> RGBA8Image {        let rawWidth = image.width
        let rawHeight = image.height
        let (outWidth, outHeight) = orientedSize(width: rawWidth, height: rawHeight, orientation: orientation)
        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        for v in 0..<outHeight {
            for u in 0..<outWidth {
                let (sx, sy) = sourceCoordinate(u: u, v: v, orientation: orientation, rawWidth: rawWidth, rawHeight: rawHeight)
                let sBase = (sy * rawWidth + sx) * 4
                let dBase = (v * outWidth + u) * 4
                out[dBase] = image.pixels[sBase]
                out[dBase + 1] = image.pixels[sBase + 1]
                out[dBase + 2] = image.pixels[sBase + 2]
                out[dBase + 3] = image.pixels[sBase + 3]
            }
        }
        return try RGBA8Image(width: outWidth, height: outHeight, pixels: out)
    }

    /// Applies an EXIF orientation to an upright top-left-origin mask.
    public static func applyOrientation(_ orientation: CGImagePropertyOrientation, to mask: Mask) throws -> Mask {
        let rawWidth = mask.width
        let rawHeight = mask.height
        let (outWidth, outHeight) = orientedSize(width: rawWidth, height: rawHeight, orientation: orientation)
        var out = [Float](repeating: 0, count: outWidth * outHeight)
        for v in 0..<outHeight {
            for u in 0..<outWidth {
                let (sx, sy) = sourceCoordinate(u: u, v: v, orientation: orientation, rawWidth: rawWidth, rawHeight: rawHeight)
                out[v * outWidth + u] = mask.values[sy * rawWidth + sx]
            }
        }
        return try Mask(width: outWidth, height: outHeight, values: out)
    }

    /// Encodes straight-alpha RGBA8 into an sRGB premultiplied-last `CGImage`.
    public static func encode(_ image: RGBA8Image) throws -> CGImage {
        var premultiplied = [UInt8](repeating: 0, count: image.pixels.count)
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            let a = image.pixels[i + 3]
            premultiplied[i] = premultiply(image.pixels[i], alpha: a)
            premultiplied[i + 1] = premultiply(image.pixels[i + 1], alpha: a)
            premultiplied[i + 2] = premultiply(image.pixels[i + 2], alpha: a)
            premultiplied[i + 3] = a
        }
        let data = Data(premultiplied)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        guard let cgImage = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return cgImage
    }

    // MARK: - Orientation

    private static func premultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        let numerator = UInt32(component) * UInt32(alpha) + 127
        return UInt8(numerator / 255)
    }

    private static func unpremultiply(_ component: UInt8, alpha: UInt8) -> UInt8 {
        let value = (Float(component) * 255 / Float(alpha)).rounded()
        return UInt8(min(max(value, 0), 255))
    }

    private static func orientedSize(width: Int, height: Int, orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            return (width, height)
        case .left, .leftMirrored, .right, .rightMirrored:
            return (height, width)
        }
    }

    private static func sourceCoordinate(u: Int, v: Int, orientation: CGImagePropertyOrientation, rawWidth: Int, rawHeight: Int) -> (Int, Int) {
        switch orientation {
        case .up:
            return (u, v)
        case .upMirrored:
            return (rawWidth - 1 - u, v)
        case .down:
            return (rawWidth - 1 - u, rawHeight - 1 - v)
        case .downMirrored:
            return (u, rawHeight - 1 - v)
        case .leftMirrored:
            return (v, u)
        case .right:
            return (v, rawHeight - 1 - u)
        case .rightMirrored:
            return (rawWidth - 1 - v, rawHeight - 1 - u)
        case .left:
            return (rawWidth - 1 - v, u)
        }
    }

    private static func isExtendedRange(_ space: CGColorSpace) -> Bool {
        guard let name = space.name else { return false }
        let string = name as String
        return string.contains("Extended") || string.contains("extended")
    }
}
