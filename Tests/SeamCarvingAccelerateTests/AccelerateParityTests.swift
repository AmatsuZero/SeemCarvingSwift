import XCTest
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
import SeamCarvingAccelerate

final class AccelerateParityTests: XCTestCase {
    func testEnergyParity() throws {
        let provider = AccelerateEnergyProvider()
        for image in try Self.fixtures() {
            let oracle = try BackwardEnergy.compute(for: image)
            let accelerate = try provider.compute(for: image)
            XCTAssertEqual(oracle.width, accelerate.width)
            XCTAssertEqual(oracle.height, accelerate.height)
            for i in 0..<oracle.values.count {
                XCTAssertEqual(oracle.values[i], accelerate.values[i], accuracy: 1e-4, "energy mismatch at \(i) in \(image.width)x\(image.height)")
            }
        }
    }

    func testBlurAndThresholdParity() throws {
        let provider = AccelerateEnergyProvider()
        for image in try Self.fixtures() {
            let oracle = try BackwardEnergy.compute(for: image, blurRadius: 2, sobelThreshold: 0.1)
            let accelerate = try provider.compute(for: image, blurRadius: 2, sobelThreshold: 0.1)
            XCTAssertEqual(oracle.width, accelerate.width)
            XCTAssertEqual(oracle.height, accelerate.height)
            for i in 0..<oracle.values.count {
                XCTAssertEqual(oracle.values[i], accelerate.values[i], accuracy: 1e-4, "blur/threshold energy mismatch at \(i) in \(image.width)x\(image.height)")
            }
        }
    }

    func testSeamParity() async throws {
        let cpu = CPUBackend()
        let accelerate = AccelerateBackend()
        for image in try Self.fixtures() {
            for orientation in [SeamOrientation.vertical, .horizontal] {
                let cpuSeam = try await cpu.findSeam(in: image, orientation: orientation, options: .init())
                let accSeam = try await accelerate.findSeam(in: image, orientation: orientation, options: .init())
                XCTAssertEqual(cpuSeam.coordinates, accSeam.coordinates, "seam mismatch for \(image.width)x\(image.height)")
                XCTAssertEqual(cpuSeam.totalCost, accSeam.totalCost, accuracy: 1e-4)
            }
        }
    }

    // MARK: - Fixtures

    static func fixtures() throws -> [RGBA8Image] {
        var images: [RGBA8Image] = []
        images.append(try RGBA8Image.solid(width: 8, height: 8, color: .init(r: 128, g: 128, b: 128, a: 255)))
        images.append(try gradient(width: 16, height: 16))
        images.append(try checkerboard(width: 9, height: 9))
        images.append(try alphaVaried(width: 12, height: 8))
        images.append(try pseudoRandom(width: 127, height: 65, seed: 7))
        images.append(try pseudoRandom(width: 1, height: 1, seed: 1))
        images.append(try pseudoRandom(width: 1, height: 9, seed: 2))
        images.append(try pseudoRandom(width: 9, height: 1, seed: 3))
        return images
    }

    static func gradient(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 255) / max(width - 1, 1))
                pixels += [v, v, v, 255]
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func checkerboard(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                pixels += [v, v, v, 255]
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func alphaVaried(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 31 + y * 7) % 256)
                let a = UInt8((x * 13 + y * 29) % 256)
                pixels += [v, v, v, a]
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    static func pseudoRandom(width: Int, height: Int, seed: UInt64) throws -> RGBA8Image {
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
