import XCTest
import CoreGraphics
import ImageIO
import CoreImage
import SeamCarvingCore
@testable import SeamCarvingAppleImaging

final class AppleImagingBridgeTests: XCTestCase {
    func testOpaqueRoundTrip() throws {
        var pixels = [UInt8]()
        for v: UInt8 in [10, 20, 30, 40, 50, 60, 70, 80, 90] {
            pixels += [v, v, v, 255]
        }
        let image = try RGBA8Image(width: 3, height: 3, pixels: pixels)
        let encoded = try CGImageBridge.encode(image)
        let decoded = try CGImageBridge.decode(encoded)
        XCTAssertEqual(decoded, image)
    }

    func testPremultipliedAlphaUnpremultiply() throws {
        // Premultiplied white at 50% alpha decodes to fully-opaque white at 50%.
        let cgImage = try Self.makeCGImage(width: 1, height: 1, pixels: [128, 128, 128, 128], alphaInfo: .premultipliedLast)
        let decoded = try CGImageBridge.decode(cgImage)
        XCTAssertEqual(decoded[0, 0], RGBA8(r: 255, g: 255, b: 255, a: 128))
    }

    func testOrientationRightRotates() throws {
        let cgImage = try Self.makeCGImage(width: 2, height: 2, pixels: [
            1, 0, 0, 255,  2, 0, 0, 255,
            3, 0, 0, 255,  4, 0, 0, 255,
        ], alphaInfo: .last)
        let decoded = try CGImageBridge.decode(cgImage, orientation: .right)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        let redBytes = stride(from: 0, to: decoded.pixels.count, by: 4).map { decoded.pixels[$0] }
        XCTAssertEqual(redBytes, [3, 1, 4, 2])
    }

    func testSixteenBitRejected() throws {
        let cgImage = try Self.make16BitImage(width: 2, height: 2)
        XCTAssertThrowsError(try CGImageBridge.decode(cgImage)) { error in
            XCTAssertEqual(error as? SeamCarvingError, .unsupportedDynamicRange)
        }
    }

    func testAppleSeamCarverResize() async throws {
        let cgImage = try Self.makeCGImage(width: 4, height: 3, pixels: Self.gradientPixels(width: 4, height: 3), alphaInfo: .last)
        let carver = try AppleSeamCarver()
        let result = try await carver.resize(cgImage, toPixelSize: try PixelSize(width: 2, height: 2))
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
    }

    func testCGImageOverloadReachesTargetDimensions() async throws {
        let image = try Self.makeCGImage(
            width: 4,
            height: 3,
            pixels: Self.gradientPixels(width: 4, height: 3),
            alphaInfo: .last
        )
        let result = try await AppleSeamCarver(
            configuration: .init(backend: .cpu, deterministic: true)
        ).resize(image, toPixelSize: try PixelSize(width: 2, height: 2))

        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
    }

    // MARK: - Pre-scale (Lanczos) opt-in

    /// Builds a `MaskPair` with a constant protection layer and a removal mask.
    private static func sampleMaskPair(width: Int, height: Int) throws -> MaskPair {
        let protectionValues = [Float](repeating: 0.5, count: width * height)
        let protection = try ProtectionLayer(
            mask: try Mask(width: width, height: height, values: protectionValues),
            strength: .soft(1)
        )
        let removalValues = [Float](repeating: 0.25, count: width * height)
        let removal = try Mask(width: width, height: height, values: removalValues)
        return try MaskPair(protectionLayers: [protection], removal: removal, removalWeight: 100)
    }

    /// NOTE: Lanczos pre-scale is an APPROXIMATION. These tests assert only that
    /// the final output reaches the EXACT requested target dimensions and that
    /// no error is thrown when masks are supplied — they do NOT assert
    /// pixel-exact parity with the exact (`.none`) mode.
    func testLanczosPreScaleReachesTargetWithMasks() async throws {
        let carver = try AppleSeamCarver()

        let scenarios: [(Int, Int, Int, Int)] = [
            (8, 6, 16, 12),   // enlargement
            (16, 12, 8, 6),   // shrink
            (16, 8, 8, 10),   // mixed width/height changes
            (8, 6, 8, 6),     // no-op resize
        ]

        for (w, h, tw, th) in scenarios {
            let cgImage = try Self.makeCGImage(width: w, height: h, pixels: Self.gradientPixels(width: w, height: h), alphaInfo: .last)
            var options = ResizeOptions()
            options.preScaleStrategy = .lanczosThenExactResidual
            options.masks = try Self.sampleMaskPair(width: w, height: h)
            let result = try await carver.resize(cgImage, toPixelSize: try PixelSize(width: tw, height: th), options: options)
            XCTAssertEqual(result.width, tw, "width mismatch for \(w)x\(h)->\(tw)x\(th)")
            XCTAssertEqual(result.height, th, "height mismatch for \(w)x\(h)->\(tw)x\(th)")
        }
    }

    func testLanczosPreScaleNoMask() async throws {
        let carver = try AppleSeamCarver()
        let cgImage = try Self.makeCGImage(width: 16, height: 12, pixels: Self.gradientPixels(width: 16, height: 12), alphaInfo: .last)
        var options = ResizeOptions()
        options.preScaleStrategy = .lanczosThenExactResidual
        let result = try await carver.resize(cgImage, toPixelSize: try PixelSize(width: 8, height: 6), options: options)
        XCTAssertEqual(result.width, 8)
        XCTAssertEqual(result.height, 6)
    }

    func testGrayscaleDecode() throws {
        let cgImage = try Self.makeGrayscaleImage(width: 2, height: 1, values: [50, 200])
        let decoded = try CGImageBridge.decode(cgImage)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 1)
        let left = decoded[0, 0]
        let right = decoded[1, 0]
        XCTAssertEqual(left.r, left.g)
        XCTAssertEqual(left.g, left.b)
        XCTAssertEqual(left.a, 255)
        XCTAssertGreaterThan(right.r, left.r)
    }

    func testBGRADecode() throws {
        let cgImage = try Self.makeBGRACImage(width: 1, height: 1, pixels: [10, 20, 30, 255])
        let decoded = try CGImageBridge.decode(cgImage)
        XCTAssertEqual(decoded[0, 0], RGBA8(r: 30, g: 20, b: 10, a: 255))
    }

    func testPaddedBytesPerRowDecode() throws {
        // 2x1 RGBA with bytesPerRow padded to 12 (extra 4 bytes per row).
        let pixels: [UInt8] = [10, 0, 0, 255, 20, 0, 0, 255, 0, 0, 0, 0]
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let cgImage = CGImage(
            width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let decoded = try CGImageBridge.decode(cgImage)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded[0, 0].r, 10)
        XCTAssertEqual(decoded[1, 0].r, 20)
    }

    func testDisplayP3Decode() throws {
        let cgImage = try Self.makeDisplayP3Image(width: 2, height: 2)
        let decoded = try CGImageBridge.decode(cgImage)
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
    }

    func testCIImageResize() async throws {
        let cgImage = try Self.makeCGImage(width: 4, height: 3, pixels: Self.gradientPixels(width: 4, height: 3), alphaInfo: .last)
        let ciImage = CIImage(cgImage: cgImage)
        let carver = try AppleSeamCarver()
        let result = try await carver.resize(ciImage, orientation: .up, toPixelSize: try PixelSize(width: 2, height: 2))
        XCTAssertEqual(result.extent.width, 2)
        XCTAssertEqual(result.extent.height, 2)
    }

    // MARK: - Fixtures

    static func makeCGImage(width: Int, height: Int, pixels: [UInt8], alphaInfo: CGImageAlphaInfo) throws -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return image
    }

    static func make16BitImage(width: Int, height: Int) throws -> CGImage {
        var data = Data(count: width * height * 8)
        for i in stride(from: 0, to: width * height * 8, by: 8) {
            data[i] = 0xFF
            data[i + 1] = 0xFF
            data[i + 2] = 0xFF
            data[i + 3] = 0xFF
            data[i + 4] = 0xFF
            data[i + 5] = 0xFF
            data[i + 6] = 0xFF
            data[i + 7] = 0xFF
        }
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Big.rawValue)
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return image
    }

    static func gradientPixels(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels += [v, v, v, 255]
            }
        }
        return pixels
    }

    static func makeGrayscaleImage(width: Int, height: Int, values: [UInt8]) throws -> CGImage {
        let data = Data(values)
        let provider = CGDataProvider(data: data as CFData)!
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return image
    }

    static func makeBGRACImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return image
    }

    static func makeDisplayP3Image(width: Int, height: Int) throws -> CGImage {
        let pixels = gradientPixels(width: width, height: height)
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return image
    }
}
