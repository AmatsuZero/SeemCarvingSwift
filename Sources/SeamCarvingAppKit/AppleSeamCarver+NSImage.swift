import AppKit
import SeamCarvingAppleRuntime
import SeamCarvingCore

public extension AppleSeamCarver {
    func resize(
        _ image: NSImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> NSImage {
        let decoded = try NSImageBridge.decode(image)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try NSImageBridge.encode(result)
    }
}
