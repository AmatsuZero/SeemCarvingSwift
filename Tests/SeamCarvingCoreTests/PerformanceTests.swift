import XCTest
@testable import SeamCarvingCore

final class PerformanceTests: XCTestCase {
    func testCPUShrinkSmoke() async throws {
        let image = try Self.randomImage(width: 32, height: 32, seed: 1)
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 24, height: 24))
        XCTAssertEqual(result.width, 24)
        XCTAssertEqual(result.height, 24)
    }

    static func randomImage(width: Int, height: Int, seed: UInt64) throws -> RGBA8Image {
        var state = seed
        var pixels = [UInt8]()
        for _ in 0..<(width * height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(state % 256)
            pixels += [v, v, v, 255]
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}
