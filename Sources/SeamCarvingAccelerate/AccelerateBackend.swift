import Foundation
@_spi(Backend) import SeamCarvingCore

public struct AccelerateEnergyProvider: Sendable {
    public init() {}

    public func compute(for image: RGBA8Image) throws -> EnergyMap {
        try AccelerateEnergy.compute(for: image)
    }
}

@_spi(Backend)
extension AccelerateEnergyProvider: BackwardEnergyProvider {}

public struct AccelerateBackend: Sendable {
    private let engine: CoreResizeEngine

    public init() {
        self.engine = CoreResizeEngine(backwardEnergyProvider: AccelerateEnergyProvider())
    }
}

@_spi(Backend)
extension AccelerateBackend: SeamCarvingBackend {
    public var identifier: String { "accelerate" }

    public func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath {
        try await engine.findSeam(in: image, orientation: orientation, options: options)
    }

    public func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        try await engine.resize(image, to: target, options: options)
    }
}
