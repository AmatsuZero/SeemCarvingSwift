import CoreGraphics
import Foundation
@_spi(Backend) import SeamCarvingCore
#if canImport(CoreImage)
import CoreImage
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct AppleSeamCarverConfiguration: Sendable, Equatable {
    public var backend: BackendPreference
    public var metalMode: MetalExecutionMode
    public var deterministic: Bool

    public init(
        backend: BackendPreference = .automatic,
        metalMode: MetalExecutionMode = .full,
        deterministic: Bool = false
    ) {
        self.backend = backend
        self.metalMode = metalMode
        self.deterministic = deterministic
    }
}

public struct AppleSeamCarver: Sendable {
    private let backend: any SeamCarvingBackend

    public init(configuration: AppleSeamCarverConfiguration = .init()) throws {
        if configuration.deterministic || configuration.backend == .cpu || configuration.backend == .automatic {
            self.backend = CPUBackend()
        } else {
            throw SeamCarvingError.invalidConfiguration("backend target not wired")
        }
    }

    public func resize(
        _ image: CGImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage {
        let decoded = try CGImageBridge.decode(image)
        let result = try await backend.resize(decoded, to: target, options: options)
        return try CGImageBridge.encode(result)
    }

    public func findSeam(
        in image: CGImage,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath {
        let decoded = try CGImageBridge.decode(image)
        return try await backend.findSeam(in: decoded, orientation: orientation, options: options)
    }
}

public extension AppleSeamCarver {
    #if canImport(CoreImage)
    func resize(
        _ image: CIImage,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CIImage {
        let decoded = try CIImageBridge.decode(image, orientation: orientation)
        let result = try await backend.resize(decoded, to: target, options: options)
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
        let result = try await backend.resize(decoded, to: target, options: options)
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
        let result = try await backend.resize(decoded, to: target, options: options)
        return try PlatformImageBridge.encode(result, scale: image.scale)
    }
    #endif

    #if canImport(AppKit)
    func resize(
        _ image: NSImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> NSImage {
        let decoded = try PlatformImageBridge.decode(image)
        let result = try await backend.resize(decoded, to: target, options: options)
        return try PlatformImageBridge.encode(result)
    }
    #endif
}
