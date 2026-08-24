@_exported import SeamCarvingAppleImaging
@_exported import SeamCarvingAppleRuntime
import SeamCarvingCore
#if canImport(CoreVideo)
import CoreVideo
import ImageIO
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// Temporary compatibility overloads for adapters that are extracted in Task 4.
public extension AppleSeamCarver {
    #if canImport(CoreVideo)
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
    #endif

    #if canImport(UIKit)
    func resize(
        _ image: UIImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> UIImage {
        let decoded = try PlatformImageBridge.decode(image)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try PlatformImageBridge.encode(result, scale: image.scale)
    }
    #endif

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    func resize(
        _ image: NSImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> NSImage {
        let decoded = try PlatformImageBridge.decode(image)
        let result = try await resize(decoded, toPixelSize: target, options: options)
        return try PlatformImageBridge.encode(result)
    }
    #endif
}
