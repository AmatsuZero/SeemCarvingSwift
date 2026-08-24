#if canImport(UIKit)
import CoreGraphics
import Foundation
import SeamCarvingAppleRuntime
import SeamCarvingCore
import UIKit
import XCTest
@testable import SeamCarvingUIKit

final class UIImageBridgeTests: XCTestCase {
    func testResizeNormalizesRightOrientationAndPreservesScale() async throws {
        let image = UIImage(
            cgImage: try makeCGImage(width: 4, height: 3),
            scale: 2,
            orientation: .right
        )
        let carver = try AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))

        let result = try await carver.resize(
            image,
            toPixelSize: try PixelSize(width: 2, height: 2)
        )

        XCTAssertEqual(result.imageOrientation, .up)
        XCTAssertEqual(result.scale, 2)
        XCTAssertEqual(Int(result.size.width * result.scale), 2)
        XCTAssertEqual(Int(result.size.height * result.scale), 2)
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
