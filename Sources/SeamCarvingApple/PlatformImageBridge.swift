import CoreGraphics
import ImageIO
import SeamCarvingCore
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PlatformImageBridge {
    #if canImport(UIKit)
    static func decode(_ image: UIImage) throws -> RGBA8Image {
        guard let cgImage = image.cgImage else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return try CGImageBridge.decode(cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    static func encode(_ image: RGBA8Image, scale: CGFloat) throws -> UIImage {
        let cgImage = try CGImageBridge.encode(image)
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    #endif

    #if canImport(AppKit)
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
    #endif
}

#if canImport(UIKit)
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif
