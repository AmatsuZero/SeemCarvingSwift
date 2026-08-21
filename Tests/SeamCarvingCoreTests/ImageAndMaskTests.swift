import XCTest
@testable import SeamCarvingCore

final class ImageAndMaskTests: XCTestCase {
    func testImageRejectsWrongByteCount() {
        XCTAssertThrowsError(
            try RGBA8Image(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 15))
        )
    }

    func testMaskRejectsWrongElementCount() {
        XCTAssertThrowsError(try Mask(width: 2, height: 2, values: [0, 1, 0]))
    }

    func testPixelRoundTrip() throws {
        var image = try RGBA8Image.solid(width: 2, height: 1, color: .init(r: 1, g: 2, b: 3, a: 4))
        image[1, 0] = .init(r: 9, g: 8, b: 7, a: 6)
        XCTAssertEqual(image[1, 0], .init(r: 9, g: 8, b: 7, a: 6))
    }
}
