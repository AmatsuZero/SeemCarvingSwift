struct CPUBackwardEnergyProvider: BackwardEnergyProvider {
    func compute(for image: RGBA8Image) throws -> EnergyMap {
        try BackwardEnergy.compute(for: image)
    }
}

public struct CPUBackend: Sendable {
    private let engine: CoreResizeEngine

    public init() {
        self.engine = CoreResizeEngine(backwardEnergyProvider: CPUBackwardEnergyProvider())
    }
}

@_spi(Backend)
extension CPUBackend: SeamCarvingBackend {
    public var identifier: String { "cpu" }

    public func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath {
        try await engine.findSeam(in: image, orientation: orientation, options: options)
    }

    public func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        try await engine.resize(image, to: target, options: options)
    }
}
