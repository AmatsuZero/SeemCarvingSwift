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

    // MARK: - Energy

    private func computeEnergy(image: RGBA8Image, masks: MaskPair) async throws -> EnergyMap {
        let device = context.device
        let width = image.width
        let height = image.height
        let pixelCount = width * height

        let imageBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let lumaBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size)!
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!

        let lumaPipeline = try await context.pipeline(named: "rgbaToLinearLuma")
        let sobelPipeline = try await context.pipeline(named: "sobelEnergy")

        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            encoder.setComputePipelineState(lumaPipeline)
            encoder.setBuffer(imageBuffer, offset: 0, index: 0)
            encoder.setBuffer(lumaBuffer, offset: 0, index: 1)
            encoder.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(pixelCount, 256), 1, 1))
            encoder.endEncoding()
        }

        // Sobel into a fresh energy buffer.
        let energyBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size)!
        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            encoder.setComputePipelineState(sobelPipeline)
            encoder.setBuffer(lumaBuffer, offset: 0, index: 0)
            encoder.setBuffer(energyBuffer, offset: 0, index: 1)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 2)
            encoder.dispatchThreads(MTLSizeMake(width, height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            encoder.endEncoding()
        }

        // Apply masks on GPU when present.
        var adjusted = readFloats(energyBuffer, count: pixelCount)
        if !masks.protectionLayers.isEmpty || masks.removal != nil {
            adjusted = try await applyMasks(base: adjusted, masks: masks, pixelCount: pixelCount)
        }

        return try EnergyMap(width: width, height: height, values: adjusted)
    }

    private func applyMasks(base: [Float], masks: MaskPair, pixelCount: Int) async throws -> [Float] {
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

        let baseBuffer = device.makeBuffer(bytes: base, length: base.count * MemoryLayout<Float>.size)!
        let outBuffer = device.makeBuffer(length: base.count * MemoryLayout<Float>.size)!
        let softMaskBuffer = softValues.isEmpty ? device.makeBuffer(length: 1)! : device.makeBuffer(bytes: softValues, length: softValues.count * MemoryLayout<Float>.size)!
        let softWeightBuffer = softWeights.isEmpty ? device.makeBuffer(length: 1)! : device.makeBuffer(bytes: softWeights, length: softWeights.count * MemoryLayout<Float>.size)!
        let hardMaskBuffer = hardValues.isEmpty ? device.makeBuffer(length: 1)! : device.makeBuffer(bytes: hardValues, length: hardValues.count * MemoryLayout<Float>.size)!
        let removalBuffer = removalValues.isEmpty ? device.makeBuffer(length: 1)! : device.makeBuffer(bytes: removalValues, length: removalValues.count * MemoryLayout<Float>.size)!

        var params = MaskParams(
            pixelCount: UInt32(pixelCount),
            softCount: UInt32(softWeights.count),
            hardCount: UInt32(hardValues.count / pixelCount),
            hasRemoval: hasRemoval ? 1 : 0,
            removalWeight: masks.removalWeight
        )
        let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<MaskParams>.size)!

        let pipeline = try await context.pipeline(named: "applyMasks")
        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
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

    private func findVerticalSeam(in image: RGBA8Image, options: ResizeOptions) async throws -> SeamPath {
        switch options.energyMode {
        case .backwardSobel:
            let energy = try await computeEnergy(image: image, masks: options.masks)
            if mode == .full {
                return try await findSeamOnGPU(energy: energy)
            }
            return try DynamicProgramming.findVerticalSeam(in: energy)
        case .forwardLuma:
            if mode == .full {
                return try await findForwardSeamOnGPU(image: image, masks: options.masks)
            }
            let luma = try LuminancePlane.luma(of: image)
            let adjustment = try options.masks.energyAdjustment(forWidth: image.width, height: image.height)
            return try ForwardEnergy.findVerticalSeam(in: luma, adjustedBaseEnergy: adjustment)
        }
    }

    /// Full GPU forward-energy dynamic programming (luma + CU/CL/CR recurrence).
    private func findForwardSeamOnGPU(image: RGBA8Image, masks: MaskPair) async throws -> SeamPath {
        let device = context.device
        let width = image.width
        let height = image.height
        let pixelCount = width * height

        let imageBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let lumaBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size)!
        let lumaPipeline = try await context.pipeline(named: "rgbaToLinearLuma")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(lumaPipeline)
            enc.setBuffer(imageBuffer, offset: 0, index: 0)
            enc.setBuffer(lumaBuffer, offset: 0, index: 1)
            enc.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(min(pixelCount, 256), 1, 1))
            enc.endEncoding()
        }

        let adjustment = try masks.energyAdjustment(forWidth: width, height: height)
        let baseValues = adjustment?.values ?? [Float](repeating: 0, count: pixelCount)
        let hasBase = adjustment != nil
        let baseBuffer = device.makeBuffer(bytes: baseValues, length: baseValues.count * MemoryLayout<Float>.size)!

        let rowA = device.makeBuffer(length: width * MemoryLayout<Float>.size)!
        let rowB = device.makeBuffer(length: width * MemoryLayout<Float>.size)!
        let parentsBuffer = device.makeBuffer(length: width * height)!
        let argminBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size)!
        let seamBuffer = device.makeBuffer(length: height * MemoryLayout<UInt32>.size)!

        let widthVal = UInt32(width)
        let heightVal = UInt32(height)
        let lumaSize = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let hasBaseVal = hasBase ? UInt32(1) : UInt32(0)

        let initPipeline = try await context.pipeline(named: "initializeDPRow")
        let accumulatePipeline = try await context.pipeline(named: "accumulateForwardDPRow")
        let reducePipeline = try await context.pipeline(named: "reduceFinalRow")
        let backtrackPipeline = try await context.pipeline(named: "backtrackSeam")

        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
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
        return try SeamPath(orientation: .vertical, coordinates: coordinates, totalCost: totalCost)
    }

    /// Full GPU dynamic programming: row-by-row serial dispatches with ping-pong
    /// float rows, an Int8 parent map, single-thread argmin, and one-thread backtrack.
    private func findSeamOnGPU(energy: EnergyMap) async throws -> SeamPath {
        let device = context.device
        let width = energy.width
        let height = energy.height

        let energyBuffer = device.makeBuffer(bytes: energy.values, length: energy.values.count * MemoryLayout<Float>.size)!
        let rowA = device.makeBuffer(length: width * MemoryLayout<Float>.size)!
        let rowB = device.makeBuffer(length: width * MemoryLayout<Float>.size)!
        let parentsBuffer = device.makeBuffer(length: width * height)!
        let argminBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size)!
        let seamBuffer = device.makeBuffer(length: height * MemoryLayout<UInt32>.size)!

        let widthVal = UInt32(width)
        let heightVal = UInt32(height)

        let initPipeline = try await context.pipeline(named: "initializeDPRow")
        let accumulatePipeline = try await context.pipeline(named: "accumulateDPRow")
        let reducePipeline = try await context.pipeline(named: "reduceFinalRow")
        let backtrackPipeline = try await context.pipeline(named: "backtrackSeam")

        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            let rows = [rowA, rowB]
            var cur = 0
            let w = widthVal
            let h = heightVal

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

            enc.setComputePipelineState(backtrackPipeline)
            enc.setBuffer(parentsBuffer, offset: 0, index: 0)
            enc.setBuffer(seamBuffer, offset: 0, index: 1)
            enc.setBuffer(argminBuffer, offset: 0, index: 2)
            withUnsafePointer(to: w) { enc.setBytes($0, length: 4, index: 3) }
            withUnsafePointer(to: h) { enc.setBytes($0, length: 4, index: 4) }
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
        return try SeamPath(orientation: .vertical, coordinates: coordinates, totalCost: totalCost)
    }

    // MARK: - Seam editing

    private func removeVerticalSeam(_ seam: SeamPath, from image: RGBA8Image, masks: MaskPair) async throws -> (RGBA8Image, MaskPair) {
        let device = context.device
        let newImage = try await removeVerticalRGBA(seam, image: image, device: device)
        let newMasks = try await removeVerticalMasks(seam, masks: masks, device: device)
        return (newImage, newMasks)
    }

    private func removeVerticalRGBA(_ seam: SeamPath, image: RGBA8Image, device: any MTLDevice) async throws -> RGBA8Image {
        let width = image.width
        let height = image.height
        let inBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let outBuffer = device.makeBuffer(length: (width - 1) * height * 4)!
        let seamBuffer = device.makeBuffer(bytes: seam.coordinates, length: seam.coordinates.count * MemoryLayout<UInt32>.size)!
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!

        let pipeline = try await context.pipeline(named: "removeVerticalRGBA")
        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
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

    private func removeVerticalMasks(_ seam: SeamPath, masks: MaskPair, device: any MTLDevice) async throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try await removeVerticalMask(seam, mask: layer.mask, device: device)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try await removeVerticalMask(seam, mask: removal, device: device)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }

    private func removeVerticalMask(_ seam: SeamPath, mask: Mask, device: any MTLDevice) async throws -> Mask {
        let width = mask.width
        let height = mask.height
        let inBuffer = device.makeBuffer(bytes: mask.values, length: mask.values.count * MemoryLayout<Float>.size)!
        let outBuffer = device.makeBuffer(length: (width - 1) * height * MemoryLayout<Float>.size)!
        let seamBuffer = device.makeBuffer(bytes: seam.coordinates, length: seam.coordinates.count * MemoryLayout<UInt32>.size)!
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!

        let pipeline = try await context.pipeline(named: "removeVerticalMask")
        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
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
        // Shrink-only sequential loop using GPU energy + GPU vertical edits and
        // CPU transpose for horizontal handling.
        try options.masks.validateDimensions(width: image.width, height: image.height)

        var current = image
        var currentMasks = options.masks
        var remainingVertical = image.width - target.width
        var remainingHorizontal = image.height - target.height

        func removeOne(_ orientation: SeamOrientation) async throws {
            let seam: SeamPath
            if orientation == .vertical {
                seam = try await findVerticalSeam(in: current, options: options)
            } else {
                let t = try SeamEditor.transpose(current)
                var to = options
                to.masks = try MaskPair(
                    protectionLayers: currentMasks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                    removal: try currentMasks.removal.map { try SeamEditor.transpose($0) },
                    removalWeight: currentMasks.removalWeight
                )
                let vs = try await findVerticalSeam(in: t, options: to)
                seam = try SeamPath(orientation: .horizontal, coordinates: vs.coordinates, totalCost: vs.totalCost)
            }

            let device = context.device
            if seam.orientation == .vertical {
                (current, currentMasks) = try await removeVerticalSeam(seam, from: current, masks: currentMasks)
            } else {
                let t = try SeamEditor.transpose(current)
                var to = currentMasks
                to = try MaskPair(
                    protectionLayers: currentMasks.protectionLayers.map { try ProtectionLayer(mask: SeamEditor.transpose($0.mask), strength: $0.strength) },
                    removal: try currentMasks.removal.map { try SeamEditor.transpose($0) },
                    removalWeight: currentMasks.removalWeight
                )
                let vs = try SeamPath(orientation: .vertical, coordinates: seam.coordinates, totalCost: seam.totalCost)
                let (tResult, tMasks) = try await removeVerticalSeam(vs, from: t, masks: to)
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
        }

        return current
    }
}

@_spi(Benchmark)
extension MetalBackend: InstrumentedSeamCarvingBackend {
    public func benchmarkResize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> (RGBA8Image, BackendPhaseDurations) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try await resize(image, to: target, options: options)
        let end = DispatchTime.now().uptimeNanoseconds
        let durations = BackendPhaseDurations(
            bridgeNS: 0, energyNS: 0, maskNS: 0, dynamicProgrammingNS: 0, backtrackNS: 0,
            editNS: 0, commandEncodingNS: 0, gpuWaitNS: end - start, totalNS: end - start,
            peakScratchBytes: UInt64(image.width * image.height * (4 + 4 + 1))
        )
        return (result, durations)
    }
}
