import CoreGraphics
import Foundation
@_exported import SeamCarvingAppleRuntime
import SeamCarvingCore
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

/// Compatibility image-framework overloads. Runtime RGBA8 operations are defined
/// in SeamCarvingAppleRuntime; these methods remain here until dedicated adapters
/// are extracted.
public extension AppleSeamCarver {
    func resize(
        _ image: CGImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage {
        let decoded = try CGImageBridge.decode(image)
        let planned = try PreScalePlanner.plan(
            image: decoded,
            masks: options.masks,
            target: target,
            strategy: options.preScaleStrategy
        )
        var plannedOptions = options
        plannedOptions.masks = planned.masks
        let result = try await resize(planned.image, toPixelSize: target, options: plannedOptions)
        return try CGImageBridge.encode(result)
    }

    func findSeam(
        in image: CGImage,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath {
        let decoded = try CGImageBridge.decode(image)
        return try await findSeam(in: decoded, orientation: orientation, options: options)
    }

    #if canImport(CoreImage)
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
    #endif

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
