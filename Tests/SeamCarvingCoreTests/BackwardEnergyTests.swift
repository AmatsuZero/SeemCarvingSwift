import XCTest
@testable import SeamCarvingCore

final class BackwardEnergyTests: XCTestCase {
    func testConstantImageHasZeroEnergy() throws {
        let image = try RGBA8Image.solid(width: 3, height: 3, color: .init(r: 128, g: 128, b: 128, a: 255))
        let energy = try BackwardEnergy.compute(for: image)
        XCTAssertEqual(energy.values, [Float](repeating: 0, count: 9))
    }

    func testVerticalStepProducesPositiveCenterEnergy() throws {
        let image = try RGBA8Image.grayscale(width: 3, height: 3, values: [
            0, 0, 255,
            0, 0, 255,
            0, 0, 255,
        ])
        let energy = try BackwardEnergy.compute(for: image)
        XCTAssertEqual(energy[0, 1], 0, accuracy: 0.0001)
        XCTAssertGreaterThan(energy[1, 1], 0)
        XCTAssertGreaterThan(energy[2, 1], 0)
    }

    // MARK: - Blur and Sobel threshold controls

    func testZeroBlurAndThresholdMatchDefault() throws {
        let image = try Self.checkerboard(width: 9, height: 9)
        let explicit = try BackwardEnergy.compute(for: image, blurRadius: 0, sobelThreshold: 0)
        let defaultEnergy = try BackwardEnergy.compute(for: image)
        XCTAssertEqual(explicit.values, defaultEnergy.values)
    }

    func testNonZeroBlurChangesEnergy() throws {
        let image = try Self.checkerboard(width: 9, height: 9)
        let sharp = try BackwardEnergy.compute(for: image, blurRadius: 0)
        let blurred = try BackwardEnergy.compute(for: image, blurRadius: 2)
        XCTAssertNotEqual(sharp.values, blurred.values)
    }

    func testSobelThresholdZeroesWeakEdges() throws {
        let image = try Self.checkerboard(width: 9, height: 9)
        let threshold: Float = 0.5
        let energy = try BackwardEnergy.compute(for: image, sobelThreshold: threshold)
        for value in energy.values {
            if value != 0 {
                XCTAssertGreaterThanOrEqual(value, threshold)
            }
        }
        // Some but not all values should be zeroed.
        XCTAssertTrue(energy.values.contains(0))
        XCTAssertTrue(energy.values.contains(where: { $0 > 0 }))
    }

    func testNegativeControlsRejected() {
        let image = try! RGBA8Image.solid(width: 3, height: 3, color: .init(r: 128, g: 128, b: 128, a: 255))
        XCTAssertThrowsError(try BackwardEnergy.compute(for: image, blurRadius: -1))
        XCTAssertThrowsError(try BackwardEnergy.compute(for: image, sobelThreshold: -1))
    }

    private static func checkerboard(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                pixels += [v, v, v, 255]
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}

extension RGBA8Image {
    /// Internal test helper: builds a grayscale image from per-pixel luma bytes.
    static func grayscale(width: Int, height: Int, values: [UInt8]) throws -> RGBA8Image {
        var pixels = [UInt8]()
        pixels.reserveCapacity(values.count * 4)
        for v in values {
            pixels.append(v)
            pixels.append(v)
            pixels.append(v)
            pixels.append(255)
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}
