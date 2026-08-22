import CoreVideo
import ImageIO
import SeamCarvingCore

enum CVPixelBufferBridge {
    static func decode(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> RGBA8Image {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32RGBA else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let raw = base.assumingMemoryBound(to: UInt8.self)
        let isBGRA = format == kCVPixelFormatType_32BGRA

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let row = raw.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let s = row.advanced(by: x * 4)
                let d = (y * width + x) * 4
                if isBGRA {
                    pixels[d] = s[2]
                    pixels[d + 1] = s[1]
                    pixels[d + 2] = s[0]
                    pixels[d + 3] = s[3]
                } else {
                    pixels[d] = s[0]
                    pixels[d + 1] = s[1]
                    pixels[d + 2] = s[2]
                    pixels[d + 3] = s[3]
                }
            }
        }

        let rawImage = try RGBA8Image(width: width, height: height, pixels: pixels)
        return try CGImageBridge.applyOrientation(orientation, to: rawImage)
    }

    static func encode(_ image: RGBA8Image) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw SeamCarvingError.unsupportedPixelFormat
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let raw = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            let row = raw.advanced(by: y * bytesPerRow)
            for x in 0..<image.width {
                let s = (y * image.width + x) * 4
                let d = x * 4
                row[d] = image.pixels[s + 2]     // B
                row[d + 1] = image.pixels[s + 1] // G
                row[d + 2] = image.pixels[s]     // R
                row[d + 3] = image.pixels[s + 3] // A
            }
        }
        return buffer
    }
}
