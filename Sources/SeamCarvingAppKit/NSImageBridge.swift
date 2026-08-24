import AppKit
import SeamCarvingAppleImaging
import SeamCarvingCore

enum NSImageBridge {
    static func decode(_ image: NSImage) throws -> RGBA8Image {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return try CGImageBridge.decode(cgImage)
    }

    static func encode(_ image: RGBA8Image) throws -> NSImage {
        let cgImage = try CGImageBridge.encode(image)
        return NSImage(cgImage: cgImage, size: NSSize(width: image.width, height: image.height))
    }
}
