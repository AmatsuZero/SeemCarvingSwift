import Foundation
@_spi(Backend) import SeamCarvingCore
@_spi(Benchmark) import SeamCarvingCore

public struct AccelerateEnergyProvider: Sendable {
    public init() {}

    public func compute(for image: RGBA8Image, blurRadius: Int = 0, sobelThreshold: Float = 0) throws -> EnergyMap {
        try AccelerateEnergy.compute(for: image, blurRadius: blurRadius, sobelThreshold: sobelThreshold)
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
        let recorder = BackendTimingRecorder()
        let result = try await engine.resizeInstrumented(image, to: target, options: options, recorder: recorder)
        let end = DispatchTime.now().uptimeNanoseconds
        var durations = recorder.snapshot()
        durations.totalNS = end - start
        let pixels = UInt64(image.width * image.height)
        let masks = UInt64(options.masks.protectionLayers.count + (options.masks.removal == nil ? 0 : 1)) * pixels * 4
        // AccelerateEnergy retains three channel planes, eight shifted planes,
        // gx/gy/scratch, luma, and the output energy map concurrently.
        let energyScratch = options.energyMode == .backwardSobel ? pixels * 64 : pixels * 13
        durations.peakScratchBytes = max(durations.peakScratchBytes, energyScratch + masks + UInt64(max(image.width, image.height) * 8))
        return (result, durations)
    }
}
