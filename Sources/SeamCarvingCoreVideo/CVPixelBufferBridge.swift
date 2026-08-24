import CoreVideo
import ImageIO
import SeamCarvingAppleImaging
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
                let source = row.advanced(by: x * 4)
                let destination = (y * width + x) * 4
                if isBGRA {
                    pixels[destination] = source[2]
                    pixels[destination + 1] = source[1]
                    pixels[destination + 2] = source[0]
                    pixels[destination + 3] = source[3]
                } else {
                    pixels[destination] = source[0]
                    pixels[destination + 1] = source[1]
                    pixels[destination + 2] = source[2]
                    pixels[destination + 3] = source[3]
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
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SeamCarvingError.unsupportedPixelFormat
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let raw = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<image.height {
            let row = raw.advanced(by: y * bytesPerRow)
            for x in 0..<image.width {
                let source = (y * image.width + x) * 4
                let destination = x * 4
                row[destination] = image.pixels[source + 2]
                row[destination + 1] = image.pixels[source + 1]
                row[destination + 2] = image.pixels[source]
                row[destination + 3] = image.pixels[source + 3]
            }
        }
        return pixelBuffer
    }
}
