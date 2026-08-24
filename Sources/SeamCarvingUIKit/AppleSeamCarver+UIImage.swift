import SeamCarvingAppleRuntime
import SeamCarvingCore
import UIKit

public extension AppleSeamCarver {
    func resize(
        _ image: UIImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> UIImage {
        let decoded = try UIImageBridge.decode(image)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try UIImageBridge.encode(result, scale: image.scale)
    }
}
