import XCTest
@testable import SeamCarvingCore

final class EnlargementTests: XCTestCase {
    func testInsertOneSeamAtRightEdge() throws {
        let image = try Self.grayImage(width: 3, height: 1, redBytes: [10, 20, 30])
        let result = try SeamEditor.insertMappedVerticalSeams([[2]], into: image, policy: .neighborAverage)
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(Self.redBytes(result), [10, 20, 30, 30])
    }

    func testInsertTwoMappedSeamsInOneRow() throws {
        let image = try Self.grayImage(width: 3, height: 1, redBytes: [10, 20, 30])
        let result = try SeamEditor.insertMappedVerticalSeams([[0], [0]], into: image, policy: .neighborAverage)
        XCTAssertEqual(result.width, 5)
        let bytes = Self.redBytes(result)
        XCTAssertEqual(bytes[0], 10)
        XCTAssertEqual(bytes[3], 20)
        XCTAssertEqual(bytes[4], 30)
        XCTAssertEqual(bytes[1], bytes[2])
    }

    func testAlphaInterpolationUsesRoundedAverage() throws {
        var pixels = [UInt8]()
        pixels += [0, 0, 0, 10]
        pixels += [0, 0, 0, 20]
        let image = try RGBA8Image(width: 2, height: 1, pixels: pixels)
        let result = try SeamEditor.insertMappedVerticalSeams([[0]], into: image, policy: .neighborAverage)
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result[1, 0].a, 15)
    }

    func testMaskInterpolation() throws {
        let mask = try Mask(width: 2, height: 1, values: [0, 1])
        let result = try SeamEditor.insertMappedVerticalSeams([[0]], into: mask)
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.values, [0, 0.5, 1])
    }

    func testEnlargeWidthOneToThree() async throws {
        let image = try Self.grayImage(width: 1, height: 3, redBytes: [50, 100, 150])
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 3, height: 3))
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 3)
    }

    func testEnlargeThreeToFive() async throws {
        let image = try Self.grayImage(width: 3, height: 2, redBytes: [10, 20, 30, 40, 50, 60])
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 5, height: 2))
        XCTAssertEqual(result.width, 5)
        XCTAssertEqual(result.height, 2)
    }

    func testEnlargeHeightViaTranspose() async throws {
        let image = try Self.grayImage(width: 3, height: 2, redBytes: [10, 20, 30, 40, 50, 60])
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 3, height: 4))
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 4)
    }

    // MARK: - Helpers

    static func grayImage(width: Int, height: Int, redBytes: [UInt8]) throws -> RGBA8Image {
        var pixels = [UInt8]()
        pixels.reserveCapacity(redBytes.count * 4)
        for r in redBytes {
            pixels.append(r)
            pixels.append(r)
            pixels.append(r)
            pixels.append(255)
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func redBytes(_ image: RGBA8Image) -> [UInt8] {
        stride(from: 0, to: image.pixels.count, by: 4).map { image.pixels[$0] }
    }
}
