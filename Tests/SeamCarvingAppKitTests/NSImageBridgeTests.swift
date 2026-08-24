#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import SeamCarvingAppleRuntime
import SeamCarvingCore
import XCTest
@testable import SeamCarvingAppKit

final class NSImageBridgeTests: XCTestCase {
    func testResizeProducesRasterAtTargetSize() async throws {
        let image = NSImage(
            cgImage: try makeCGImage(width: 4, height: 3),
            size: NSSize(width: 4, height: 3)
        )
        let carver = try AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))

        let result = try await carver.resize(
            image,
            toPixelSize: try PixelSize(width: 2, height: 2)
        )

        let outputCG = try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(outputCG.width, 2)
        XCTAssertEqual(outputCG.height, 2)
    }

    private func makeCGImage(width: Int, height: Int) throws -> CGImage {
        let pixels = [UInt8](repeating: 255, count: width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        return try XCTUnwrap(CGImage(
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
        ))
    }
}
#endif
