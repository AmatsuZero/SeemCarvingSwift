import XCTest
@_spi(Backend) import SeamCarvingCore

final class MaskAndObjectRemovalTests: XCTestCase {
    // MARK: - Seam selection with masks

    func testSoftProtectStripeAvoided() async throws {
        let image = try Self.solid(width: 4, height: 3)
        let layer = try ProtectionLayer(mask: Self.columnMask(width: 4, height: 3, column: 0), strength: .soft(100_000))
        let masks = try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1000)
        let seam = try await CPUBackend().findSeam(in: image, orientation: .vertical, options: ResizeOptions(masks: masks))
        XCTAssertEqual(seam.coordinates, [1, 1, 1])
    }

    func testRemovalStripeSelected() async throws {
        let image = try Self.solid(width: 4, height: 3)
        let masks = try MaskPair(protectionLayers: [], removal: Self.columnMask(width: 4, height: 3, column: 2), removalWeight: 100_000)
        let seam = try await CPUBackend().findSeam(in: image, orientation: .vertical, options: ResizeOptions(masks: masks))
        XCTAssertEqual(seam.coordinates, [2, 2, 2])
    }

    func testHardProtectFullRowThrows() async throws {
        let image = try Self.solid(width: 4, height: 4)
        let layer = try ProtectionLayer(mask: Self.rowMask(width: 4, height: 4, row: 1), strength: .hard)
        let masks = try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1000)
        do {
            _ = try await CPUBackend().findSeam(in: image, orientation: .vertical, options: ResizeOptions(masks: masks))
            XCTFail("expected noFeasibleSeam")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .noFeasibleSeam)
        }
    }

    func testHardProtectWinsOverRemoval() async throws {
        let image = try Self.solid(width: 4, height: 3)
        let hard = try ProtectionLayer(mask: Self.columnMask(width: 4, height: 3, column: 0), strength: .hard)
        let masks = try MaskPair(protectionLayers: [hard], removal: Self.columnMask(width: 4, height: 3, column: 0), removalWeight: 100_000)
        let seam = try await CPUBackend().findSeam(in: image, orientation: .vertical, options: ResizeOptions(masks: masks))
        XCTAssertEqual(seam.coordinates, [1, 1, 1])
    }

    func testMismatchedMaskDimensionsThrow() async throws {
        let image = try Self.solid(width: 4, height: 3)
        let layer = try ProtectionLayer(mask: try Mask(width: 3, height: 3, values: [Float](repeating: 0, count: 9)), strength: .soft(10))
        let masks = try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1000)
        do {
            _ = try await CPUBackend().findSeam(in: image, orientation: .vertical, options: ResizeOptions(masks: masks))
            XCTFail("expected throw")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .invalidConfiguration("protection mask dimensions must match image"))
        }
    }

    func testInvalidWeightsThrow() throws {
        let mask = try Mask(width: 2, height: 2, values: [0, 0, 0, 0])
        XCTAssertThrowsError(try ProtectionLayer(mask: mask, strength: .soft(-1)))
        XCTAssertThrowsError(try ProtectionLayer(mask: mask, strength: .soft(.nan)))
        XCTAssertThrowsError(try ProtectionLayer(mask: mask, strength: .soft(.infinity)))
        XCTAssertThrowsError(try MaskPair(protectionLayers: [], removal: nil, removalWeight: -1))
        XCTAssertThrowsError(try MaskPair(protectionLayers: [], removal: nil, removalWeight: .nan))
        XCTAssertThrowsError(try MaskPair(protectionLayers: [], removal: nil, removalWeight: .infinity))
    }

    // MARK: - Masks shrink with image

    func testRemovalObjectFullyRemovedOverMultipleSeams() async throws {
        let image = try Self.grayColumns(width: 4, height: 3, values: [10, 100, 200, 250])
        var removalValues = [Float](repeating: 0, count: 12)
        for y in 0..<3 {
            removalValues[y * 4 + 1] = 1
            removalValues[y * 4 + 2] = 1
        }
        let masks = try MaskPair(protectionLayers: [], removal: try Mask(width: 4, height: 3, values: removalValues), removalWeight: 100_000)
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 2, height: 3), options: ResizeOptions(masks: masks))
        XCTAssertEqual(Self.grayColumnValues(result), [10, 250])
    }

    // MARK: - Object removal

    func testRemoveObjectRemovesObject() async throws {
        let image = try Self.grayColumns(width: 3, height: 3, values: [10, 100, 200])
        let removalMask = try Self.columnMask(width: 3, height: 3, column: 1)
        let result = try await SeamCarver().removeObject(from: image, removalMask: removalMask, restoreOriginalSize: false)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 3)
        XCTAssertEqual(Self.grayColumnValues(result), [10, 200])
    }

    func testRemoveObjectRestoresSize() async throws {
        let image = try Self.grayColumns(width: 3, height: 3, values: [10, 100, 200])
        let removalMask = try Self.columnMask(width: 3, height: 3, column: 1)
        let result = try await SeamCarver().removeObject(from: image, removalMask: removalMask, restoreOriginalSize: true)
        XCTAssertEqual(result.width, 3)
        XCTAssertEqual(result.height, 3)
    }

    // MARK: - Helpers

    static func solid(width: Int, height: Int) throws -> RGBA8Image {
        try RGBA8Image.solid(width: width, height: height, color: .init(r: 128, g: 128, b: 128, a: 255))
    }

    static func columnMask(width: Int, height: Int, column: Int) throws -> Mask {
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            values[y * width + column] = 1
        }
        return try Mask(width: width, height: height, values: values)
    }

    static func rowMask(width: Int, height: Int, row: Int) throws -> Mask {
        var values = [Float](repeating: 0, count: width * height)
        for x in 0..<width {
            values[row * width + x] = 1
        }
        return try Mask(width: width, height: height, values: values)
    }

    static func grayColumns(width: Int, height: Int, values: [UInt8]) throws -> RGBA8Image {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<height {
            for x in 0..<width {
                let v = values[x]
                pixels.append(v)
                pixels.append(v)
                pixels.append(v)
                pixels.append(255)
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func grayColumnValues(_ image: RGBA8Image) -> [UInt8] {
        (0..<image.width).map { image[$0, 0].r }
    }
}
