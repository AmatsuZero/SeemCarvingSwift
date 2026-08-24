import CoreVideo
import ImageIO
import SeamCarvingAppleRuntime
import SeamCarvingCore
import XCTest
@testable import SeamCarvingCoreVideo

final class CVPixelBufferBridgeTests: XCTestCase {
    func testBGRADecodePreservesChannelsAndAlpha() throws {
        let buffer = try makePixelBuffer(format: kCVPixelFormatType_32BGRA, width: 2, height: 2)
        CVPixelBufferLockBaseAddress(buffer, [])

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        pixels[0] = 10; pixels[1] = 20; pixels[2] = 30; pixels[3] = 255
        pixels[4] = 40; pixels[5] = 50; pixels[6] = 60; pixels[7] = 128
        pixels[bytesPerRow] = 70; pixels[bytesPerRow + 1] = 80; pixels[bytesPerRow + 2] = 90; pixels[bytesPerRow + 3] = 255
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let decoded = try CVPixelBufferBridge.decode(buffer, orientation: .up)
        XCTAssertEqual(decoded[0, 0], RGBA8(r: 30, g: 20, b: 10, a: 255))
        XCTAssertEqual(decoded[1, 0], RGBA8(r: 60, g: 50, b: 40, a: 128))
        XCTAssertEqual(decoded[0, 1], RGBA8(r: 90, g: 80, b: 70, a: 255))
    }

    func testResizeReachesTargetDimensions() async throws {
        let buffer = try makePixelBuffer(format: kCVPixelFormatType_32BGRA, width: 4, height: 3)
        let carver = try AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))

        let result = try await carver.resize(
            buffer,
            orientation: .up,
            toPixelSize: try PixelSize(width: 2, height: 2)
        )

        XCTAssertEqual(CVPixelBufferGetWidth(result), 2)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 2)
    }

    private func makePixelBuffer(format: OSType, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &pixelBuffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }
}
