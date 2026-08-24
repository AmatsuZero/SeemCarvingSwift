import XCTest
import CoreGraphics
import CoreImage
import ImageIO
import SeamCarvingApple
import SeamCarvingCore

final class SeamCarvingAppleCompatibilityTests: XCTestCase {
    func testFacadePreservesRGBA8CGImageAndCIImageEntryPoints() async throws {
        let source = try RGBA8Image(width: 2, height: 2, pixels: [
            255, 0, 0, 255,   0, 255, 0, 255,
            0, 0, 255, 255,   255, 255, 0, 255,
        ])
        let target = try PixelSize(width: 1, height: 2)
        let carver = try AppleSeamCarver(configuration: .init(
            backend: .cpu,
            metalMode: .full,
            deterministic: true
        ))

        let rgbaResult = try await carver.resize(source, toPixelSize: target)
        XCTAssertEqual(rgbaResult.width, 1)
        XCTAssertEqual(rgbaResult.height, 2)

        let cgImage = try Self.makeCGImage(width: 2, height: 2, pixels: source.pixels)
        let cgResult = try await carver.resize(cgImage, toPixelSize: target)
        XCTAssertEqual(cgResult.width, 1)
        XCTAssertEqual(cgResult.height, 2)

        let seam = try await carver.findSeam(in: cgImage, orientation: .vertical)
        XCTAssertEqual(seam.orientation, .vertical)
        XCTAssertEqual(seam.coordinates.count, cgImage.height)

        let ciImage = CIImage(cgImage: cgImage)
        let ciResult = try await carver.resize(
            ciImage,
            orientation: .up,
            toPixelSize: target
        )
        XCTAssertEqual(Int(ciResult.extent.width), 1)
        XCTAssertEqual(Int(ciResult.extent.height), 2)
    }

    private static func makeCGImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
