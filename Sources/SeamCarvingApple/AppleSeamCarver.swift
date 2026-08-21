import CoreGraphics
import Foundation
@_spi(Backend) import SeamCarvingCore

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
