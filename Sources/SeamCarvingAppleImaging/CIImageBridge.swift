import CoreImage
import CoreGraphics
import SeamCarvingCore

enum CIImageBridge {
    static func decode(_ image: CIImage, orientation: CGImagePropertyOrientation) throws -> RGBA8Image {
        if let space = image.colorSpace, (space.name as String?)?.contains("Extended") == true {
            throw SeamCarvingError.unsupportedDynamicRange
        }
        let oriented = image.oriented(orientation)
        let context = CIContext()
        guard let cgImage = context.createCGImage(oriented, from: oriented.extent) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return try CGImageBridge.decode(cgImage)
    }

    static func encode(_ image: RGBA8Image) throws -> CIImage {
        let cgImage = try CGImageBridge.encode(image)
        return CIImage(cgImage: cgImage)
    }
}
