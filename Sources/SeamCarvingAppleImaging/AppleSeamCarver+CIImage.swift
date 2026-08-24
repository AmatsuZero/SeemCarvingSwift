import CoreGraphics
import CoreImage
import SeamCarvingAppleRuntime
import SeamCarvingCore

public extension AppleSeamCarver {
    func resize(
        _ image: CIImage,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CIImage {
        let decoded = try CIImageBridge.decode(image, orientation: orientation)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try CIImageBridge.encode(result)
    }
}
