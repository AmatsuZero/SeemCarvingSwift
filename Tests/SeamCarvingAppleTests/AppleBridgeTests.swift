import XCTest
import CoreVideo
import ImageIO
import SeamCarvingCore
@testable import SeamCarvingApple

final class AppleBridgeTests: XCTestCase {
    func testCVPixelBufferRoundTrip() throws {
        let width = 2
        let height = 2
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let raw = base.assumingMemoryBound(to: UInt8.self)
        raw[0] = 10; raw[1] = 20; raw[2] = 30; raw[3] = 255
        raw[4] = 40; raw[5] = 50; raw[6] = 60; raw[7] = 128
        raw[bytesPerRow] = 70; raw[bytesPerRow + 1] = 80; raw[bytesPerRow + 2] = 90; raw[bytesPerRow + 3] = 255
        raw[bytesPerRow + 4] = 100; raw[bytesPerRow + 5] = 110; raw[bytesPerRow + 6] = 120; raw[bytesPerRow + 7] = 255
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let decoded = try CVPixelBufferBridge.decode(buffer, orientation: .up)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(decoded[0, 0], RGBA8(r: 30, g: 20, b: 10, a: 255))
        XCTAssertEqual(decoded[1, 0], RGBA8(r: 60, g: 50, b: 40, a: 128))
        XCTAssertEqual(decoded[0, 1], RGBA8(r: 90, g: 80, b: 70, a: 255))
    }
}
