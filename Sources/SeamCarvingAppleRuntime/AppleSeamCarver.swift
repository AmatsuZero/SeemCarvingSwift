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
        self.backend = try BackendFactory.default.make(configuration)
    }

    init(configuration: AppleSeamCarverConfiguration, factory: BackendFactory) throws {
        self.backend = try factory.make(configuration)
    }

    public func resize(
        _ image: RGBA8Image,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image {
        try await backend.resize(image, to: target, options: options)
    }

    public func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath {
        try await backend.findSeam(in: image, orientation: orientation, options: options)
    }
}
