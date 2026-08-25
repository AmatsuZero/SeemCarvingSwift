import Foundation

struct CPUBackwardEnergyProvider: BackwardEnergyProvider {
    func compute(for image: RGBA8Image, blurRadius: Int, sobelThreshold: Float) throws -> EnergyMap {
        try BackwardEnergy.compute(for: image, blurRadius: blurRadius, sobelThreshold: sobelThreshold)
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
        let clock = ContinuousClock()
        let start = clock.now
        let recorder = BackendTimingRecorder()
        let result = try await engine.resizeInstrumented(image, to: target, options: options, recorder: recorder)
        var durations = recorder.snapshot()
        durations.totalNS = elapsedNanoseconds(start.duration(to: clock.now))
        let (pixelCount, overflow) = image.width.multipliedReportingOverflow(by: image.height)
        guard !overflow else { throw SeamCarvingError.invalidDimensions }
        let pixels = UInt64(pixelCount)
        let frameBytes = pixels * UInt64(MemoryLayout<Float>.size)
        let maskCount = UInt64(options.masks.protectionLayers.count + (options.masks.removal == nil ? 0 : 1))
        let maskBytes = maskCount * frameBytes
        // BackwardEnergy retains luma and energy; dynamic programming retains
        // a bounded row buffer and parent offsets.
        let estimatedScratch = frameBytes + frameBytes + maskBytes + UInt64(max(image.width, image.height)) * 8
        durations.peakScratchBytes = max(durations.peakScratchBytes, estimatedScratch)
        return (result, durations)
    }
}
