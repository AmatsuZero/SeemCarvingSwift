import XCTest
@preconcurrency import Metal
@_spi(Backend) import SeamCarvingCore
@testable import SeamCarvingMetal

final class MetalKernelTests: XCTestCase {
    func testPassthrough() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal device available")
        }
        let context = try MetalContext.makeDefault()
        let device = await context.device

        let input: [UInt8] = [
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16,
        ]
        let inBuffer = device.makeBuffer(bytes: input, length: input.count)!
        let outBuffer = device.makeBuffer(length: input.count)!
        var size: [UInt32] = [2, 2]
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<UInt32>.size * 2)!

        let pipeline = try await context.pipeline(named: "rgbaPassthrough")
        try await context.submit { commandBuffer in
            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(inBuffer, offset: 0, index: 0)
            encoder.setBuffer(outBuffer, offset: 0, index: 1)
            encoder.setBuffer(sizeBuffer, offset: 0, index: 2)
            let threads = MTLSizeMake(4, 1, 1)
            encoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(4, 1, 1))
            encoder.endEncoding()
        }

        let output = [UInt8](UnsafeRawBufferPointer(start: outBuffer.contents(), count: input.count))
        XCTAssertEqual(output, input)
    }

    func testSobelEnergyParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device available") }
        let context = try MetalContext.makeDefault()
        let device = context.device
        let image = try Self.grayGradient(width: 17, height: 19)
        let oracle = try BackwardEnergy.compute(for: image)

        let width = image.width
        let height = image.height
        let pixelCount = width * height
        let imageBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let lumaBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size)!
        var size = SIMD2<UInt32>(UInt32(width), UInt32(height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!

        let lumaPipeline = try await context.pipeline(named: "rgbaToLinearLuma")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(lumaPipeline)
            enc.setBuffer(imageBuffer, offset: 0, index: 0)
            enc.setBuffer(lumaBuffer, offset: 0, index: 1)
            enc.dispatchThreads(MTLSizeMake(pixelCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(256, 1, 1))
            enc.endEncoding()
        }

        let energyBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size)!
        let sobelPipeline = try await context.pipeline(named: "sobelEnergy")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(sobelPipeline)
            enc.setBuffer(lumaBuffer, offset: 0, index: 0)
            enc.setBuffer(energyBuffer, offset: 0, index: 1)
            enc.setBuffer(sizeBuffer, offset: 0, index: 2)
            enc.dispatchThreads(MTLSizeMake(width, height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            enc.endEncoding()
        }
        let gpu = [Float](UnsafeBufferPointer(start: energyBuffer.contents().assumingMemoryBound(to: Float.self), count: pixelCount))
        XCTAssertEqual(gpu.count, oracle.values.count)
        for i in 0..<pixelCount {
            XCTAssertEqual(gpu[i], oracle.values[i], accuracy: 1e-4, "energy mismatch at \(i)")
        }
    }

    func testTransposeRGBAParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device available") }
        let context = try MetalContext.makeDefault()
        let device = context.device
        let image = try Self.grayGradient(width: 3, height: 2)
        let oracle = try SeamEditor.transpose(image)

        var size = SIMD2<UInt32>(UInt32(image.width), UInt32(image.height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!
        let inBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let outBuffer = device.makeBuffer(length: image.pixels.count)!

        let pipeline = try await context.pipeline(named: "transposeRGBA")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(inBuffer, offset: 0, index: 0)
            enc.setBuffer(outBuffer, offset: 0, index: 1)
            enc.setBuffer(sizeBuffer, offset: 0, index: 2)
            enc.dispatchThreads(MTLSizeMake(image.height, image.width, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            enc.endEncoding()
        }
        let gpu = [UInt8](UnsafeRawBufferPointer(start: outBuffer.contents(), count: image.pixels.count))
        XCTAssertEqual(gpu, oracle.pixels)
    }

    func testTransposeRGBANonSquareParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device available") }
        let context = try MetalContext.makeDefault()
        let device = context.device
        // Device-sized non-square fixture: 17x11 (transpose -> 11x17).
        let image = try Self.grayGradient(width: 17, height: 11)
        let oracle = try SeamEditor.transpose(image)

        var size = SIMD2<UInt32>(UInt32(image.width), UInt32(image.height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!
        let inBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let outBuffer = device.makeBuffer(length: image.pixels.count)!

        let pipeline = try await context.pipeline(named: "transposeRGBA")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(inBuffer, offset: 0, index: 0)
            enc.setBuffer(outBuffer, offset: 0, index: 1)
            enc.setBuffer(sizeBuffer, offset: 0, index: 2)
            enc.dispatchThreads(MTLSizeMake(image.height, image.width, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            enc.endEncoding()
        }
        let gpu = [UInt8](UnsafeRawBufferPointer(start: outBuffer.contents(), count: image.pixels.count))
        XCTAssertEqual(gpu, oracle.pixels)
    }

    func testTransposeMaskNonSquareParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device available") }
        let context = try MetalContext.makeDefault()
        let device = context.device
        let image = try Self.grayGradient(width: 17, height: 11)
        var maskValues = [Float]()
        for y in 0..<image.height {
            for x in 0..<image.width {
                maskValues.append(Float((x * 61 + y * 37) % 256) / 255.0)
            }
        }
        let mask = try Mask(width: image.width, height: image.height, values: maskValues)
        let oracle = try SeamEditor.transpose(mask)

        var size = SIMD2<UInt32>(UInt32(mask.width), UInt32(mask.height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!
        let inBuffer = device.makeBuffer(bytes: mask.values, length: mask.values.count * MemoryLayout<Float>.size)!
        let outBuffer = device.makeBuffer(length: mask.values.count * MemoryLayout<Float>.size)!

        let pipeline = try await context.pipeline(named: "transposeMask")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(inBuffer, offset: 0, index: 0)
            enc.setBuffer(outBuffer, offset: 0, index: 1)
            enc.setBuffer(sizeBuffer, offset: 0, index: 2)
            enc.dispatchThreads(MTLSizeMake(mask.height, mask.width, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            enc.endEncoding()
        }
        let gpu = [Float](UnsafeBufferPointer(start: outBuffer.contents().assumingMemoryBound(to: Float.self), count: mask.values.count))
        XCTAssertEqual(gpu, oracle.values)
    }

    func testRemoveAndInsertParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device available") }
        let context = try MetalContext.makeDefault()
        let device = context.device
        let image = try Self.grayGradient(width: 4, height: 3)

        // Remove parity.
        let seam = try SeamPath(orientation: .vertical, coordinates: [1, 2, 1], totalCost: 0)
        let removedOracle = try SeamEditor.remove(seam, from: image)
        var size = SIMD2<UInt32>(UInt32(image.width), UInt32(image.height))
        let sizeBuffer = device.makeBuffer(bytes: &size, length: MemoryLayout<SIMD2<UInt32>>.size)!
        let seamBuffer = device.makeBuffer(bytes: seam.coordinates, length: seam.coordinates.count * MemoryLayout<UInt32>.size)!
        let inBuffer = device.makeBuffer(bytes: image.pixels, length: image.pixels.count)!
        let outBuffer = device.makeBuffer(length: (image.width - 1) * image.height * 4)!
        let removePipeline = try await context.pipeline(named: "removeVerticalRGBA")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(removePipeline)
            enc.setBuffer(inBuffer, offset: 0, index: 0)
            enc.setBuffer(outBuffer, offset: 0, index: 1)
            enc.setBuffer(seamBuffer, offset: 0, index: 2)
            enc.setBuffer(sizeBuffer, offset: 0, index: 3)
            enc.dispatchThreads(MTLSizeMake(image.width - 1, image.height, 1), threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            enc.endEncoding()
        }
        let removedGPU = [UInt8](UnsafeRawBufferPointer(start: outBuffer.contents(), count: (image.width - 1) * image.height * 4))
        XCTAssertEqual(removedGPU, removedOracle.pixels)

        // Insert parity (one mapped seam per row).
        let seams: [[UInt32]] = [[1, 1, 1]]
        let insertedOracle = try SeamEditor.insertMappedVerticalSeams(seams, into: image, policy: .neighborAverage)
        var positions = [UInt32]()
        for y in 0..<image.height {
            for seamPos in seams {
                positions.append(seamPos[y])
            }
        }
        let positionsBuffer = device.makeBuffer(bytes: positions, length: positions.count * MemoryLayout<UInt32>.size)!
        var count = UInt32(seams.count)
        let countBuffer = device.makeBuffer(bytes: &count, length: MemoryLayout<UInt32>.size)!
        let insertOutBuffer = device.makeBuffer(length: (image.width + seams.count) * image.height * 4)!
        let insertPipeline = try await context.pipeline(named: "insertMappedVerticalRGBA")
        try await context.submit { cb in
            guard let enc = cb.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(insertPipeline)
            enc.setBuffer(inBuffer, offset: 0, index: 0)
            enc.setBuffer(insertOutBuffer, offset: 0, index: 1)
            enc.setBuffer(positionsBuffer, offset: 0, index: 2)
            enc.setBuffer(countBuffer, offset: 0, index: 3)
            enc.setBuffer(sizeBuffer, offset: 0, index: 4)
            enc.dispatchThreads(MTLSizeMake(image.height, 1, 1), threadsPerThreadgroup: MTLSizeMake(image.height, 1, 1))
            enc.endEncoding()
        }
        let insertedGPU = [UInt8](UnsafeRawBufferPointer(start: insertOutBuffer.contents(), count: (image.width + seams.count) * image.height * 4))
        XCTAssertEqual(insertedGPU, insertedOracle.pixels)
    }

    static func grayGradient(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels += [v, v, v, 255]
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}
