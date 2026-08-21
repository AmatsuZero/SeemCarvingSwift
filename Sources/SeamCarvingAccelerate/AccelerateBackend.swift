import Foundation
@_spi(Backend) import SeamCarvingCore
@_spi(Benchmark) import SeamCarvingCore

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

@_spi(Benchmark)
extension AccelerateBackend: InstrumentedSeamCarvingBackend {
    public func benchmarkResize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> (RGBA8Image, BackendPhaseDurations) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try await resize(image, to: target, options: options)
        let end = DispatchTime.now().uptimeNanoseconds
        let durations = BackendPhaseDurations(
            bridgeNS: 0, energyNS: 0, maskNS: 0, dynamicProgrammingNS: 0, backtrackNS: 0,
            editNS: 0, commandEncodingNS: 0, gpuWaitNS: 0, totalNS: end - start, peakScratchBytes: 0
        )
        return (result, durations)
    }
}
