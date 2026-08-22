import XCTest
@preconcurrency import Metal
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
import SeamCarvingMetal

final class MetalParityTests: XCTestCase {
    func testFindSeamParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
        let context = try MetalContext.makeDefault()
        let cpu = CPUBackend()
        let metal = MetalBackend(context: context)
        for image in try Self.fixtures() {
            for orientation in [SeamOrientation.vertical, .horizontal] {
                let cpuSeam = try await cpu.findSeam(in: image, orientation: orientation, options: .init())
                let metalSeam = try await metal.findSeam(in: image, orientation: orientation, options: .init())
                XCTAssertEqual(cpuSeam.coordinates, metalSeam.coordinates, "seam mismatch for \(image.width)x\(image.height)")
                XCTAssertEqual(cpuSeam.totalCost, metalSeam.totalCost, accuracy: 1e-4)
            }
        }
    }

    func testResizeParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
        let context = try MetalContext.makeDefault()
        let cpu = CPUBackend()
        let metal = MetalBackend(context: context)
        let image = try Self.gradient(width: 16, height: 12)
        let target = try PixelSize(width: 12, height: 10)
        let cpuResult = try await cpu.resize(image, to: target, options: .init())
        let metalResult = try await metal.resize(image, to: target, options: .init())
        XCTAssertEqual(cpuResult.width, metalResult.width)
        XCTAssertEqual(cpuResult.height, metalResult.height)
        XCTAssertEqual(cpuResult.pixels, metalResult.pixels)
    }

    func testUnsupportedResizePoliciesUseReferenceSemantics() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
        let context = try MetalContext.makeDefault()
        let cpu = CPUBackend()
        let metal = MetalBackend(context: context)
        let image = try Self.gradient(width: 10, height: 8)

        let enlargedTarget = try PixelSize(width: 12, height: 9)
        XCTAssertEqual(metal.effectiveIdentifier(from: try PixelSize(width: image.width, height: image.height), to: enlargedTarget, options: .init()), "cpu-fallback")
        let cpuEnlarged = try await cpu.resize(image, to: enlargedTarget, options: .init())
        let metalEnlarged = try await metal.resize(image, to: enlargedTarget, options: .init())
        XCTAssertEqual(cpuEnlarged.pixels, metalEnlarged.pixels)

        var adaptive = ResizeOptions()
        adaptive.dimensionOrder = .adaptiveNormalizedCost
        let adaptiveTarget = try PixelSize(width: 8, height: 6)
        XCTAssertEqual(metal.effectiveIdentifier(from: try PixelSize(width: image.width, height: image.height), to: adaptiveTarget, options: adaptive), "cpu-fallback")
        let cpuAdaptive = try await cpu.resize(image, to: adaptiveTarget, options: adaptive)
        let metalAdaptive = try await metal.resize(image, to: adaptiveTarget, options: adaptive)
        XCTAssertEqual(cpuAdaptive.pixels, metalAdaptive.pixels)
    }

    func testForwardDPParity() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
        let context = try MetalContext.makeDefault()
        let cpu = CPUBackend()
        let metal = MetalBackend(context: context)
        var options = ResizeOptions()
        options.energyMode = .forwardLuma
        for image in try Self.fixtures() {
            let cpuSeam = try await cpu.findSeam(in: image, orientation: .vertical, options: options)
            let metalSeam = try await metal.findSeam(in: image, orientation: .vertical, options: options)
            XCTAssertEqual(cpuSeam.coordinates, metalSeam.coordinates, "forward seam mismatch for \(image.width)x\(image.height)")
            XCTAssertEqual(cpuSeam.totalCost, metalSeam.totalCost, accuracy: 1e-3)
        }
    }

    // MARK: - Fixtures

    static func fixtures() throws -> [RGBA8Image] {
        [
            try RGBA8Image.solid(width: 8, height: 8, color: .init(r: 128, g: 128, b: 128, a: 255)),
            try gradient(width: 16, height: 12),
            try checkerboard(width: 9, height: 9),
            try pseudoRandom(width: 17, height: 19, seed: 11),
            try pseudoRandom(width: 1, height: 9, seed: 2),
            try pseudoRandom(width: 9, height: 1, seed: 3),
        ]
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
