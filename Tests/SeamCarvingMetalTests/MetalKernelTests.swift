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
}
