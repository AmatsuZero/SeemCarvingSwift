import CoreVideo
import ImageIO
import SeamCarvingAppleRuntime
import SeamCarvingCore

public extension AppleSeamCarver {
    func resize(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CVPixelBuffer {
        let decoded = try CVPixelBufferBridge.decode(pixelBuffer, orientation: orientation)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try CVPixelBufferBridge.encode(result)
    }
}
