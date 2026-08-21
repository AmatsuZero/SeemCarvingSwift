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
