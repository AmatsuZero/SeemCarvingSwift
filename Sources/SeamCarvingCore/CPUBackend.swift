import Foundation

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

@_spi(Benchmark)
extension CPUBackend: InstrumentedSeamCarvingBackend {
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
