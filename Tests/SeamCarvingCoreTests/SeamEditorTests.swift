import XCTest
@testable import SeamCarvingCore

final class SeamEditorTests: XCTestCase {
    func testRemoveVerticalSeamPixelOrder() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let seam = try SeamPath(orientation: .vertical, coordinates: [1, 1], totalCost: 0)
        let result = try SeamEditor.remove(seam, from: image)
        XCTAssertEqual(Self.redBytes(result), [1, 3, 4, 6])
    }

    func testRemoveVerticalSeamRejectsInvalidLength() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let short = try SeamPath(orientation: .vertical, coordinates: [1], totalCost: 0)
        let long = try SeamPath(orientation: .vertical, coordinates: [1, 1, 1], totalCost: 0)
        XCTAssertThrowsError(try SeamEditor.remove(short, from: image))
        XCTAssertThrowsError(try SeamEditor.remove(long, from: image))
    }

    func testRemoveVerticalSeamRejectsOutOfRange() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let seam = try SeamPath(orientation: .vertical, coordinates: [1, 5], totalCost: 0)
        XCTAssertThrowsError(try SeamEditor.remove(seam, from: image))
    }

    func testRemoveVerticalSeamRejectsDiscontinuous() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let seam = try SeamPath(orientation: .vertical, coordinates: [0, 2], totalCost: 0)
        XCTAssertThrowsError(try SeamEditor.remove(seam, from: image))
    }

    func testDoubleTransposeReturnsOriginal() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        XCTAssertEqual(try SeamEditor.transpose(try SeamEditor.transpose(image)), image)

        let mask = try Mask(width: 3, height: 2, values: [0, 0.5, 1, 0.25, 0.75, 0.125])
        XCTAssertEqual(try SeamEditor.transpose(try SeamEditor.transpose(mask)), mask)
    }

    func testHorizontalRemovalEqualsManualPerColumnRemoval() throws {
        let image = try Self.image(redBytes: [1, 2, 3, 4, 5, 6], width: 3, height: 2)
        let seam = try SeamPath(orientation: .horizontal, coordinates: [1, 0, 1], totalCost: 0)
        let result = try SeamEditor.remove(seam, from: image)
        XCTAssertEqual(Self.redBytes(result), [1, 5, 3])
    }

    func testMaskRemovalMatchesImageRemovalShape() throws {
        let mask = try Mask(width: 3, height: 2, values: [0, 0.5, 1, 0.25, 0.75, 0.125])
        let seam = try SeamPath(orientation: .vertical, coordinates: [1, 1], totalCost: 0)
        let result = try SeamEditor.remove(seam, from: mask)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.values, [0, 1, 0.25, 0.125])
    }

    // MARK: - Helpers

    static func image(redBytes: [UInt8], width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        pixels.reserveCapacity(redBytes.count * 4)
        for r in redBytes {
            pixels.append(r)
            pixels.append(0)
            pixels.append(0)
            pixels.append(255)
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func redBytes(_ image: RGBA8Image) -> [UInt8] {
        stride(from: 0, to: image.pixels.count, by: 4).map { image.pixels[$0] }
    }
}
