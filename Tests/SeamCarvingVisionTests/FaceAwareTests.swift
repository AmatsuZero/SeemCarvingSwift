import os
import XCTest
import CoreGraphics
import ImageIO
import SeamCarvingCore
import SeamCarvingApple
@testable import SeamCarvingVision

final class FaceAwareTests: XCTestCase {
    func testUprightRectConversion() {
        let rect = uprightRect(from: CGRect(x: 0.0, y: 0.5, width: 0.5, height: 0.5), imageWidth: 100, imageHeight: 100)
        // Vision box (0, 0.5)-(0.5, 1.0) maps to top-left (0, 0) size (50, 50).
        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.width, 50)
        XCTAssertEqual(rect.height, 50)
    }

    func testFaceRegionValidation() {
        XCTAssertThrowsError(try FaceRegion(x: -1, y: 0, width: 10, height: 10, confidence: 1))
        XCTAssertThrowsError(try FaceRegion(x: 0, y: 0, width: 0, height: 10, confidence: 1))
        XCTAssertThrowsError(try FaceRegion(x: 0, y: 0, width: 10, height: 10, confidence: 1.5))
        XCTAssertThrowsError(try FaceRegion(x: 0, y: 0, width: 10, height: 10, confidence: .nan))
        XCTAssertNoThrow(try FaceRegion(x: 0, y: 0, width: 10, height: 10, confidence: 1))
    }

    func testRasterizerFiltersAndClips() throws {
        let size = try PixelSize(width: 10, height: 10)
        let params = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 100, minimumConfidence: 0.5)
        let low = try FaceRegion(x: 0, y: 0, width: 2, height: 2, confidence: 0.4)
        let high = try FaceRegion(x: 0, y: 0, width: 2, height: 2, confidence: 0.6)
        let outside = try FaceRegion(x: 20, y: 20, width: 2, height: 2, confidence: 0.9)
        let mask = try FaceMaskRasterizer.rasterize(regions: [low, high, outside], size: size, policy: .caireInspired(params))
        // low filtered out, outside clipped to nothing, high rasterized at (0,0)-(2,2).
        XCTAssertEqual(mask[0, 0], 1)
        XCTAssertEqual(mask[2, 0], 0)
        XCTAssertEqual(mask[0, 2], 0)
    }

    func testEnergyComposerAppendsAndZerosRemoval() throws {
        let user = try ProtectionLayer(mask: try Mask(width: 3, height: 3, values: [Float](repeating: 0, count: 9)), strength: .hard)
        let removalValues: [Float] = [0, 1, 0, 0, 1, 0, 0, 1, 0]
        let removal = try Mask(width: 3, height: 3, values: removalValues)
        let userMasks = try MaskPair(protectionLayers: [user], removal: removal, removalWeight: 10)
        let faceValues: [Float] = [0, 0, 0, 0, 1, 0, 0, 0, 0]
        let faceMask = try Mask(width: 3, height: 3, values: faceValues)
        let params = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 500, minimumConfidence: 0)
        let composed = try EnergyComposer.compose(userMasks: userMasks, faceMask: faceMask, policy: .caireInspired(params))

        XCTAssertEqual(composed.protectionLayers.count, 2)
        XCTAssertEqual(composed.removal?.values[4], 0)  // face overrides removal
        XCTAssertEqual(composed.removal?.values[1], 1)  // untouched removal
    }

    func testDetectOnceCadenceCallsDetectorOnce() async throws {
        let image = try Self.grayImage(width: 4, height: 4)
        let region = try FaceRegion(x: 1, y: 1, width: 2, height: 2, confidence: 1)
        let detector = FakeDetector(regions: [region])
        let policy = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 100, minimumConfidence: 0)
        let carver = try FaceAwareSeamCarver(detector: detector, policy: .caireInspired(policy), cadence: .detectOnceAndTransformMask)
        _ = try await carver.resize(image, orientation: .up, toPixelSize: try PixelSize(width: 3, height: 3))
        XCTAssertEqual(detector.callCount, 1)
    }

    func testRedetectCadenceCallsDetectorPerPass() async throws {
        let image = try Self.grayImage(width: 4, height: 4)
        let region = try FaceRegion(x: 1, y: 1, width: 2, height: 2, confidence: 1)
        let detector = FakeDetector(regions: [region])
        let policy = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 100, minimumConfidence: 0)
        let carver = try FaceAwareSeamCarver(detector: detector, policy: .caireInspired(policy), cadence: .redetectEveryPass)
        _ = try await carver.resize(image, orientation: .up, toPixelSize: try PixelSize(width: 2, height: 2))
        // 4x4 -> 2x2 removes 2 vertical + 2 horizontal = 4 edits = 4 detections.
        XCTAssertEqual(detector.callCount, 4)
    }

    func testRedetectCadenceRejectsEnlargement() async throws {
        let image = try Self.grayImage(width: 4, height: 4)
        let detector = FakeDetector(regions: [])
        let policy = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 100, minimumConfidence: 0)
        let carver = try FaceAwareSeamCarver(detector: detector, policy: .caireInspired(policy), cadence: .redetectEveryPass)

        do {
            _ = try await carver.resize(image, orientation: .up, toPixelSize: try PixelSize(width: 5, height: 4))
            XCTFail("redetectEveryPass should reject enlargement")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("redetectEveryPass currently supports seam removal only; use detectOnceAndTransformMask for enlargement")
            )
        }
    }

    func testRedetectCadenceHonorsHeightThenWidthOrder() async throws {
        let image = try Self.grayImage(width: 4, height: 3)
        let detector = RecordingDetector()
        let policy = try CaireInspiredParameters(expansionFraction: 0, protectionWeight: 100, minimumConfidence: 0)
        let carver = try FaceAwareSeamCarver(detector: detector, policy: .caireInspired(policy), cadence: .redetectEveryPass)

        var options = ResizeOptions()
        options.dimensionOrder = .heightThenWidth
        _ = try await carver.resize(image, orientation: .up, toPixelSize: try PixelSize(width: 2, height: 2), options: options)

        XCTAssertEqual(detector.sizes.map { "\($0.0)x\($0.1)" }, ["4x3", "4x2", "3x2"])
    }

    // MARK: - Fixtures

    static func grayImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels += [v, v, v, 255]
            }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

final class FakeDetector: FaceDetecting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _callCount = 0
    private let regions: [FaceRegion]

    init(regions: [FaceRegion]) {
        self.regions = regions
    }

    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion] {
        lock.withLock { _callCount += 1 }
        return regions
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }
}

final class RecordingDetector: FaceDetecting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _sizes: [(Int, Int)] = []

    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion] {
        lock.withLock { _sizes.append((image.width, image.height)) }
        return []
    }

    var sizes: [(Int, Int)] {
        lock.withLock { _sizes }
    }
}
