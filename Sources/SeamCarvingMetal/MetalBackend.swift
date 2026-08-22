import Foundation
@preconcurrency import Metal
@_spi(Backend) import SeamCarvingCore
@_spi(Benchmark) import SeamCarvingCore

public struct MetalBackend: Sendable {
    private let context: MetalContext
    private let mode: MetalExecutionMode

    public init(context: MetalContext, mode: MetalExecutionMode = .full) {
        self.context = context
        self.mode = mode
    }

    /// Returns the implementation path used for a request. Metal currently
    /// delegates enlargement and adaptive ordering to the reference CPU
    /// backend so those requests preserve the package-wide semantics.
    public func effectiveIdentifier(from source: PixelSize, to target: PixelSize, options: ResizeOptions) -> String {
        if target.width > source.width || target.height > source.height || options.dimensionOrder == .adaptiveNormalizedCost {
            return "cpu-fallback"
        }
        return identifier
    }

    // MARK: - Energy

    private func computeEnergy(image: RGBA8Image, masks: MaskPair, recorder: BackendTimingRecorder? = nil) async throws -> EnergyMap {
        let phaseStart = DispatchTime.now().uptimeNanoseconds
        let device = context.device
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        recorder?.recordScratch(bytes: UInt64(pixelCount * (4 + 4 + 4) + MemoryLayout<SIMD2<UInt32>>.stride))

        let imageBuffer = try requiredBuffer(bytes: image.pixels, device: device)
        let lumaBuffer = try requiredBuffer(length: pixelCount * MemoryLayout<Float>.size, device: device)
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = try requiredBuffer(value: &size, device: device)

        let lumaPipeline = try await context.pipeline(named: "rgbaToLinearLuma")
        let sobelPipeline = try await context.pipeline(named: "sobelEnergy")

        try await submit(recorder: recorder) { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            encoder.setComputePipelineState(lumaPipeline)
            encoder.setBuffer(imageBuffer, offset: 0, index: 0)
            encoder.setBuffer(lumaBuffer, offset: 0, index: 1)
            encoder.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(pixelCount, 256), 1, 1))
            encoder.endEncoding()
        }

        // Sobel into a fresh energy buffer.
        let energyBuffer = try requiredBuffer(length: pixelCount * MemoryLayout<Float>.size, device: device)
        try await submit(recorder: recorder) { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            encoder.setComputePipelineState(sobelPipeline)
            encoder.setBuffer(lumaBuffer, offset: 0, index: 0)
            encoder.setBuffer(energyBuffer, offset: 0, index: 1)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 2)
            encoder.dispatchThreads(MTLSizeMake(width, height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            encoder.endEncoding()
        }

        // Apply masks on GPU when present.
        var adjusted = readFloats(energyBuffer, count: pixelCount)
        recorder?.record(\.energyNS, elapsed: DispatchTime.now().uptimeNanoseconds - phaseStart)
        if !masks.protectionLayers.isEmpty || masks.removal != nil {
            adjusted = try await applyMasks(base: adjusted, masks: masks, pixelCount: pixelCount, recorder: recorder)
        }

        return try EnergyMap(width: width, height: height, values: adjusted)
    }

    private func applyMasks(base: [Float], masks: MaskPair, pixelCount: Int, recorder: BackendTimingRecorder? = nil) async throws -> [Float] {
        let phaseStart = DispatchTime.now().uptimeNanoseconds
        defer { recorder?.record(\.maskNS, elapsed: DispatchTime.now().uptimeNanoseconds - phaseStart) }
        let device = context.device
        var softValues: [Float] = []
        var softWeights: [Float] = []
        var hardValues: [Float] = []
        var removalValues: [Float] = []
        for layer in masks.protectionLayers {
            switch layer.strength {
            case .soft(let w):
                softValues.append(contentsOf: layer.mask.values)
                softWeights.append(w)
            case .hard:
                hardValues.append(contentsOf: layer.mask.values)
            }
        }
        let hasRemoval = masks.removal != nil
        if let removal = masks.removal {
            removalValues = removal.values
        }
        recorder?.recordScratch(bytes: UInt64(base.count * 4 * 2 + (softValues.count + hardValues.count + removalValues.count) * 4 + 32))

        let baseBuffer = try requiredBuffer(bytes: base, device: device)
        let outBuffer = try requiredBuffer(length: base.count * MemoryLayout<Float>.size, device: device)
        let softMaskBuffer = try requiredBuffer(bytes: softValues, device: device)
        let softWeightBuffer = try requiredBuffer(bytes: softWeights, device: device)
        let hardMaskBuffer = try requiredBuffer(bytes: hardValues, device: device)
        let removalBuffer = try requiredBuffer(bytes: removalValues, device: device)

        var params = MaskParams(
            pixelCount: UInt32(pixelCount),
            softCount: UInt32(softWeights.count),
            hardCount: UInt32(hardValues.count / pixelCount),
            hasRemoval: hasRemoval ? 1 : 0,
            removalWeight: masks.removalWeight
        )
        let paramsBuffer = try requiredBuffer(value: &params, device: device)

        let pipeline = try await context.pipeline(named: "applyMasks")
        try await submit(recorder: recorder) { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(baseBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
            encoder.setBuffer(softMaskBuffer, offset: 0, index: 2)
            encoder.setBuffer(softWeightBuffer, offset: 0, index: 3)
            encoder.setBuffer(hardMaskBuffer, offset: 0, index: 4)
            encoder.setBuffer(removalBuffer, offset: 0, index: 5)
            encoder.setBuffer(paramsBuffer, offset: 0, index: 6)
            encoder.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(pixelCount, 256), 1, 1))
            encoder.endEncoding()
        }
        return readFloats(outBuffer, count: pixelCount)
    }

    // MARK: - Seam finding

    private func findVerticalSeam(in image: RGBA8Image, options: ResizeOptions, recorder: BackendTimingRecorder? = nil) async throws -> SeamPath {
        switch options.energyMode {
        case .backwardSobel:
            let energy = try await computeEnergy(image: image, masks: options.masks, recorder: recorder)
            if mode == .full {
                let start = DispatchTime.now().uptimeNanoseconds
                defer { recorder?.record(\.dynamicProgrammingNS, elapsed: DispatchTime.now().uptimeNanoseconds - start) }
                return try await findSeamOnGPU(energy: energy, recorder: recorder)
            }
            let start = DispatchTime.now().uptimeNanoseconds
            defer { recorder?.record(\.dynamicProgrammingNS, elapsed: DispatchTime.now().uptimeNanoseconds - start) }
            return try DynamicProgramming.findVerticalSeam(in: energy)
        case .forwardLuma:
            if mode == .full {
                let start = DispatchTime.now().uptimeNanoseconds
                defer { recorder?.record(\.dynamicProgrammingNS, elapsed: DispatchTime.now().uptimeNanoseconds - start) }
                return try await findForwardSeamOnGPU(image: image, masks: options.masks, recorder: recorder)
            }
            let luma = try LuminancePlane.luma(of: image)
            let adjustment = try options.masks.energyAdjustment(forWidth: image.width, height: image.height)
            let start = DispatchTime.now().uptimeNanoseconds
            defer { recorder?.record(\.dynamicProgrammingNS, elapsed: DispatchTime.now().uptimeNanoseconds - start) }
            return try ForwardEnergy.findVerticalSeam(in: luma, adjustedBaseEnergy: adjustment)
        }
    }

    /// Full GPU forward-energy dynamic programming (luma + CU/CL/CR recurrence).
    private func findForwardSeamOnGPU(image: RGBA8Image, masks: MaskPair, recorder: BackendTimingRecorder? = nil) async throws -> SeamPath {
        let device = context.device
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        let energyStart = DispatchTime.now().uptimeNanoseconds
        recorder?.recordScratch(bytes: UInt64(pixelCount * (4 + 4 + 4) + width * 8 + pixelCount + height * 4 + 32))

        let imageBuffer = try requiredBuffer(bytes: image.pixels, device: device)
        let lumaBuffer = try requiredBuffer(length: pixelCount * MemoryLayout<Float>.size, device: device)
        let lumaPipeline = try await context.pipeline(named: "rgbaToLinearLuma")
        try await submit(recorder: recorder) { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            enc.setComputePipelineState(lumaPipeline)
            enc.setBuffer(imageBuffer, offset: 0, index: 0)
            enc.setBuffer(lumaBuffer, offset: 0, index: 1)
            enc.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(pixelCount, 256), 1, 1))
            enc.endEncoding()
        }
        recorder?.record(\.energyNS, elapsed: DispatchTime.now().uptimeNanoseconds - energyStart)

        let adjustment = try masks.energyAdjustment(forWidth: width, height: height)
        let baseValues = adjustment?.values ?? [Float](repeating: 0, count: pixelCount)
        let hasBase = adjustment != nil
        let baseBuffer = try requiredBuffer(bytes: baseValues, device: device)

        let rowA = try requiredBuffer(length: width * MemoryLayout<Float>.size, device: device)
        let rowB = try requiredBuffer(length: width * MemoryLayout<Float>.size, device: device)
        let parentsBuffer = try requiredBuffer(length: width * height, device: device)
        let argminBuffer = try requiredBuffer(length: MemoryLayout<UInt32>.size, device: device)
        let seamBuffer = try requiredBuffer(length: height * MemoryLayout<UInt32>.size, device: device)

        let widthVal = UInt32(width)
        let heightVal = UInt32(height)
        let lumaSize = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let hasBaseVal = hasBase ? UInt32(1) : UInt32(0)

        let initPipeline = try await context.pipeline(named: "initializeDPRow")
        let accumulatePipeline = try await context.pipeline(named: "accumulateForwardDPRow")
        let reducePipeline = try await context.pipeline(named: "reduceFinalRow")
        let backtrackPipeline = try await context.pipeline(named: "backtrackSeam")

        try await submit(recorder: recorder) { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            let rows = [rowA, rowB]
            var cur = 0

            enc.setComputePipelineState(initPipeline)
            enc.setBuffer(baseBuffer, offset: 0, index: 0)
            enc.setBuffer(rows[0], offset: 0, index: 1)
            withUnsafePointer(to: widthVal) { enc.setBytes($0, length: 4, index: 2) }
            enc.dispatchThreads(MTLSizeMake(width, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(width, 256), 1, 1))

            enc.setComputePipelineState(accumulatePipeline)
            enc.setBuffer(lumaBuffer, offset: 0, index: 3)
            enc.setBuffer(baseBuffer, offset: 0, index: 4)
            withUnsafePointer(to: lumaSize) { enc.setBytes($0, length: 8, index: 5) }
            withUnsafePointer(to: hasBaseVal) { enc.setBytes($0, length: 4, index: 7) }
            for y in 1..<height {
                let yVal = UInt32(y)
                enc.setBuffer(rows[cur], offset: 0, index: 0)
                enc.setBuffer(rows[1 - cur], offset: 0, index: 1)
                enc.setBuffer(parentsBuffer, offset: 0, index: 2)
                withUnsafePointer(to: yVal) { enc.setBytes($0, length: 4, index: 6) }
                enc.dispatchThreads(MTLSizeMake(width, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(width, 256), 1, 1))
                cur = 1 - cur
            }

            enc.setComputePipelineState(reducePipeline)
            enc.setBuffer(rows[cur], offset: 0, index: 0)
            enc.setBuffer(argminBuffer, offset: 0, index: 1)
            withUnsafePointer(to: widthVal) { enc.setBytes($0, length: 4, index: 2) }
            enc.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))

            enc.endEncoding()
        }

        let backtrackStart = DispatchTime.now().uptimeNanoseconds
        try await submit(recorder: recorder) { cb in
            guard let enc = cb.makeComputeCommandEncoder() else {
                throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable")
            }
            enc.setComputePipelineState(backtrackPipeline)
            enc.setBuffer(parentsBuffer, offset: 0, index: 0)
            enc.setBuffer(seamBuffer, offset: 0, index: 1)
            enc.setBuffer(argminBuffer, offset: 0, index: 2)
            withUnsafePointer(to: widthVal) { enc.setBytes($0, length: 4, index: 3) }
            withUnsafePointer(to: heightVal) { enc.setBytes($0, length: 4, index: 4) }
            enc.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
            enc.endEncoding()
        }
        let argmin = argminBuffer.contents().assumingMemoryBound(to: UInt32.self)[0]
        guard argmin != UInt32.max else {
            throw SeamCarvingError.noFeasibleSeam
        }
        let coordinates = [UInt32](UnsafeBufferPointer(start: seamBuffer.contents().assumingMemoryBound(to: UInt32.self), count: height))
        let lastRow = (height - 1) % 2 == 0 ? rowA : rowB
        let totalCost = lastRow.contents().assumingMemoryBound(to: Float.self)[Int(argmin)]
        recorder?.record(\.backtrackNS, elapsed: DispatchTime.now().uptimeNanoseconds - backtrackStart)
        return try SeamPath(orientation: .vertical, coordinates: coordinates, totalCost: totalCost)
    }

    /// Full GPU dynamic programming: row-by-row serial dispatches with ping-pong
    /// float rows, an Int8 parent map, single-thread argmin, and one-thread backtrack.
    private func findSeamOnGPU(energy: EnergyMap, recorder: BackendTimingRecorder? = nil) async throws -> SeamPath {
        let device = context.device
        let width = energy.width
        let height = energy.height
        recorder?.recordScratch(bytes: UInt64(width * height * 4 + width * 8 + width * height + height * 4 + 32))

        let energyBuffer = try requiredBuffer(bytes: energy.values, device: device)
        let rowA = try requiredBuffer(length: width * MemoryLayout<Float>.size, device: device)
        let rowB = try requiredBuffer(length: width * MemoryLayout<Float>.size, device: device)
        let parentsBuffer = try requiredBuffer(length: width * height, device: device)
        let argminBuffer = try requiredBuffer(length: MemoryLayout<UInt32>.size, device: device)
        let seamBuffer = try requiredBuffer(length: height * MemoryLayout<UInt32>.size, device: device)

        let widthVal = UInt32(width)
        let heightVal = UInt32(height)

        let initPipeline = try await context.pipeline(named: "initializeDPRow")
        let accumulatePipeline = try await context.pipeline(named: "accumulateDPRow")
        let reducePipeline = try await context.pipeline(named: "reduceFinalRow")
        let backtrackPipeline = try await context.pipeline(named: "backtrackSeam")

        try await submit(recorder: recorder) { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            let rows = [rowA, rowB]
            var cur = 0
            let w = widthVal

            enc.setComputePipelineState(initPipeline)
            enc.setBuffer(energyBuffer, offset: 0, index: 0)
            enc.setBuffer(rows[0], offset: 0, index: 1)
            withUnsafePointer(to: w) { enc.setBytes($0, length: 4, index: 2) }
            enc.dispatchThreads(MTLSizeMake(width, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(width, 256), 1, 1))

            enc.setComputePipelineState(accumulatePipeline)
            enc.setBuffer(energyBuffer, offset: 0, index: 3)
            for y in 1..<height {
                let size = SIMD2<UInt32>(UInt32(width), UInt32(y))
                enc.setBuffer(rows[cur], offset: 0, index: 0)
                enc.setBuffer(rows[1 - cur], offset: 0, index: 1)
                enc.setBuffer(parentsBuffer, offset: 0, index: 2)
                withUnsafePointer(to: size) { enc.setBytes($0, length: 8, index: 4) }
                enc.dispatchThreads(MTLSizeMake(width, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(width, 256), 1, 1))
                cur = 1 - cur
            }

            enc.setComputePipelineState(reducePipeline)
            enc.setBuffer(rows[cur], offset: 0, index: 0)
            enc.setBuffer(argminBuffer, offset: 0, index: 1)
            withUnsafePointer(to: w) { enc.setBytes($0, length: 4, index: 2) }
            enc.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))

            enc.endEncoding()
        }

        let backtrackStart = DispatchTime.now().uptimeNanoseconds
        try await submit(recorder: recorder) { cb in
            guard let enc = cb.makeComputeCommandEncoder() else {
                throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable")
            }
            enc.setComputePipelineState(backtrackPipeline)
            enc.setBuffer(parentsBuffer, offset: 0, index: 0)
            enc.setBuffer(seamBuffer, offset: 0, index: 1)
            enc.setBuffer(argminBuffer, offset: 0, index: 2)
            withUnsafePointer(to: widthVal) { enc.setBytes($0, length: 4, index: 3) }
            withUnsafePointer(to: heightVal) { enc.setBytes($0, length: 4, index: 4) }
            enc.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
            enc.endEncoding()
        }
        let argmin = argminBuffer.contents().assumingMemoryBound(to: UInt32.self)[0]
        guard argmin != UInt32.max else {
            throw SeamCarvingError.noFeasibleSeam
        }
        let coordinates = [UInt32](UnsafeBufferPointer(start: seamBuffer.contents().assumingMemoryBound(to: UInt32.self), count: height))

        let lastRow = (height - 1) % 2 == 0 ? rowA : rowB
        let totalCost = lastRow.contents().assumingMemoryBound(to: Float.self)[Int(argmin)]
        recorder?.record(\.backtrackNS, elapsed: DispatchTime.now().uptimeNanoseconds - backtrackStart)
        return try SeamPath(orientation: .vertical, coordinates: coordinates, totalCost: totalCost)
    }

    // MARK: - Seam editing

    private func removeVerticalSeam(_ seam: SeamPath, from image: RGBA8Image, masks: MaskPair, recorder: BackendTimingRecorder? = nil) async throws -> (RGBA8Image, MaskPair) {
        let phaseStart = DispatchTime.now().uptimeNanoseconds
        defer { recorder?.record(\.editNS, elapsed: DispatchTime.now().uptimeNanoseconds - phaseStart) }
        let device = context.device
        let newImage = try await removeVerticalRGBA(seam, image: image, device: device, recorder: recorder)
        let newMasks = try await removeVerticalMasks(seam, masks: masks, device: device, recorder: recorder)
        return (newImage, newMasks)
    }

    private func removeVerticalRGBA(_ seam: SeamPath, image: RGBA8Image, device: any MTLDevice, recorder: BackendTimingRecorder? = nil) async throws -> RGBA8Image {
        let width = image.width
        let height = image.height
        recorder?.recordScratch(bytes: UInt64(width * height * 4 + (width - 1) * height * 4 + height * 4 + 8))
        let inBuffer = try requiredBuffer(bytes: image.pixels, device: device)
        let outBuffer = try requiredBuffer(length: (width - 1) * height * 4, device: device)
        let seamBuffer = try requiredBuffer(bytes: seam.coordinates, device: device)
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = try requiredBuffer(value: &size, device: device)

        let pipeline = try await context.pipeline(named: "removeVerticalRGBA")
        try await submit(recorder: recorder) { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(inBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
            encoder.setBuffer(seamBuffer, offset: 0, index: 2)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 3)
            encoder.dispatchThreads(MTLSizeMake(width - 1, height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            encoder.endEncoding()
        }
        let pixels = [UInt8](UnsafeRawBufferPointer(start: outBuffer.contents(), count: (width - 1) * height * 4))
        return try RGBA8Image(width: width - 1, height: height, pixels: pixels)
    }

    private func removeVerticalMasks(_ seam: SeamPath, masks: MaskPair, device: any MTLDevice, recorder: BackendTimingRecorder? = nil) async throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try await removeVerticalMask(seam, mask: layer.mask, device: device, recorder: recorder)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try await removeVerticalMask(seam, mask: removal, device: device, recorder: recorder)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }

    private func removeVerticalMask(_ seam: SeamPath, mask: Mask, device: any MTLDevice, recorder: BackendTimingRecorder? = nil) async throws -> Mask {
        let width = mask.width
        let height = mask.height
        let inBuffer = try requiredBuffer(bytes: mask.values, device: device)
        let outBuffer = try requiredBuffer(length: (width - 1) * height * MemoryLayout<Float>.size, device: device)
        let seamBuffer = try requiredBuffer(bytes: seam.coordinates, device: device)
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = try requiredBuffer(value: &size, device: device)

        let pipeline = try await context.pipeline(named: "removeVerticalMask")
        try await submit(recorder: recorder) { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw SeamCarvingError.metalExecutionFailed("compute encoder unavailable") }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(inBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
            encoder.setBuffer(seamBuffer, offset: 0, index: 2)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 3)
            encoder.dispatchThreads(MTLSizeMake(width - 1, height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            encoder.endEncoding()
        }
        let values = readFloats(outBuffer, count: (width - 1) * height)
        return try Mask(width: width - 1, height: height, values: values)
    }

    // MARK: - Public SPI

    private func submit(
        recorder: BackendTimingRecorder?,
        _ encode: @Sendable (any MTLCommandBuffer) throws -> Void
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        let encodingNS = try await context.submit(encode)
        recorder?.record(\.commandEncodingNS, elapsed: encodingNS)
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        recorder?.record(\.gpuWaitNS, elapsed: elapsed > encodingNS ? elapsed - encodingNS : 0)
    }

    private func requiredBuffer(length: Int, device: any MTLDevice) throws -> any MTLBuffer {
        guard let buffer = device.makeBuffer(length: max(1, length), options: .storageModeShared) else {
            throw SeamCarvingError.metalExecutionFailed("buffer allocation failed (\(length) bytes)")
        }
        return buffer
    }

    private func requiredBuffer<T>(bytes values: [T], device: any MTLDevice) throws -> any MTLBuffer {
        guard !values.isEmpty else { return try requiredBuffer(length: 1, device: device) }
        guard let buffer = values.withUnsafeBytes({ raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }) else {
            throw SeamCarvingError.metalExecutionFailed("buffer allocation failed (\(values.count) elements)")
        }
        return buffer
    }

    private func requiredBuffer<T>(value: inout T, device: any MTLDevice) throws -> any MTLBuffer {
        guard let buffer = withUnsafePointer(to: &value, { pointer in
            device.makeBuffer(bytes: pointer, length: MemoryLayout<T>.stride, options: .storageModeShared)
        }) else {
            throw SeamCarvingError.metalExecutionFailed("buffer allocation failed (\(MemoryLayout<T>.stride) bytes)")
        }
        return buffer
    }

    private func readFloats(_ buffer: any MTLBuffer, count: Int) -> [Float] {
        let ptr = buffer.contents().assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }
}

struct MaskParams {
    var pixelCount: UInt32
    var softCount: UInt32
    var hardCount: UInt32
    var hasRemoval: UInt32
    var removalWeight: Float
}

@_spi(Backend)
extension MetalBackend: SeamCarvingBackend {
    public var identifier: String { "metal" }

    public func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath {
        switch orientation {
        case .vertical:
            return try await findVerticalSeam(in: image, options: options)
        case .horizontal:
            let transposed = try SeamEditor.transpose(image)
            var transposedOptions = options
            transposedOptions.masks = try MaskPair(
                protectionLayers: options.masks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                removal: try options.masks.removal.map { try SeamEditor.transpose($0) },
                removalWeight: options.masks.removalWeight
            )
            let seam = try await findVerticalSeam(in: transposed, options: transposedOptions)
            return try SeamPath(orientation: .horizontal, coordinates: seam.coordinates, totalCost: seam.totalCost)
        }
    }

    public func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        try await resize(image, to: target, options: options, recorder: nil)
    }

    private func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions, recorder: BackendTimingRecorder?) async throws -> RGBA8Image {
        // The Metal kernels currently implement the shrink path.  Delegate
        // enlargement and adaptive ordering to the reference backend rather
        // than silently returning the wrong extent or ordering seams by a
        // different policy.
        if target.width > image.width || target.height > image.height || options.dimensionOrder == .adaptiveNormalizedCost {
            return try await CPUBackend().resize(image, to: target, options: options)
        }

        // Shrink-only sequential loop using GPU energy + GPU vertical edits and
        // CPU transpose for horizontal handling.
        try options.masks.validateDimensions(width: image.width, height: image.height)

        var current = image
        var currentMasks = options.masks
        var remainingVertical = image.width - target.width
        var remainingHorizontal = image.height - target.height
        var completedEdits = 0
        let totalEdits = remainingVertical + remainingHorizontal

        func removeOne(_ orientation: SeamOrientation) async throws {
            let seam: SeamPath
            if orientation == .vertical {
                var currentOptions = options
                currentOptions.masks = currentMasks
                seam = try await findVerticalSeam(in: current, options: currentOptions, recorder: recorder)
            } else {
                let t = try SeamEditor.transpose(current)
                var to = options
                to.masks = try MaskPair(
                    protectionLayers: currentMasks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                    removal: try currentMasks.removal.map { try SeamEditor.transpose($0) },
                    removalWeight: currentMasks.removalWeight
                )
                let vs = try await findVerticalSeam(in: t, options: to, recorder: recorder)
                seam = try SeamPath(orientation: .horizontal, coordinates: vs.coordinates, totalCost: vs.totalCost)
            }

            let device = context.device
            if seam.orientation == .vertical {
                (current, currentMasks) = try await removeVerticalSeam(seam, from: current, masks: currentMasks, recorder: recorder)
            } else {
                let t = try SeamEditor.transpose(current)
                var to = currentMasks
                to = try MaskPair(
                    protectionLayers: currentMasks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                    removal: try currentMasks.removal.map { try SeamEditor.transpose($0) },
                    removalWeight: currentMasks.removalWeight
                )
                let vs = try SeamPath(orientation: .vertical, coordinates: seam.coordinates, totalCost: seam.totalCost)
                let (tResult, tMasks) = try await removeVerticalSeam(vs, from: t, masks: to, recorder: recorder)
                current = try SeamEditor.transpose(tResult)
                currentMasks = try MaskPair(
                    protectionLayers: tMasks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                    removal: try tMasks.removal.map { try SeamEditor.transpose($0) },
                    removalWeight: tMasks.removalWeight
                )
            }
            _ = device
        }

        while remainingVertical > 0 || remainingHorizontal > 0 {
            try Task.checkCancellation()
            if options.dimensionOrder == .heightThenWidth {
                if remainingHorizontal > 0 {
                    try await removeOne(.horizontal)
                    remainingHorizontal -= 1
                } else {
                    try await removeOne(.vertical)
                    remainingVertical -= 1
                }
            } else {
                if remainingVertical > 0 {
                    try await removeOne(.vertical)
                    remainingVertical -= 1
                } else {
                    try await removeOne(.horizontal)
                    remainingHorizontal -= 1
                }
            }
            try Task.checkCancellation()
            completedEdits += 1
            options.progress?(ResizeProgress(
                completedEdits: completedEdits,
                totalEdits: totalEdits,
                size: try PixelSize(width: current.width, height: current.height)
            ))
        }

        return current
    }
}

@_spi(Benchmark)
extension MetalBackend: InstrumentedSeamCarvingBackend {
    public func benchmarkResize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> (RGBA8Image, BackendPhaseDurations) {
        let start = DispatchTime.now().uptimeNanoseconds
        let recorder = BackendTimingRecorder()
        let result = try await resize(image, to: target, options: options, recorder: recorder)
        let end = DispatchTime.now().uptimeNanoseconds
        var durations = recorder.snapshot()
        durations.totalNS = end - start
        durations.peakScratchBytes = max(durations.peakScratchBytes, UInt64(image.width * image.height * (4 + 4 + 1)))
        return (result, durations)
    }
}
