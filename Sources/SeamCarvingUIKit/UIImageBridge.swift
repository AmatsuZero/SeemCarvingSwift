#if canImport(UIKit)
import ImageIO
import SeamCarvingAppleImaging
import SeamCarvingCore
import UIKit

enum UIImageBridge {
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
}

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
