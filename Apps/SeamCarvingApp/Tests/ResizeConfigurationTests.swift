// ResizeConfigurationTests.swift
//
// NOTE: This test target is NOT yet wired into the build. The `SeamCarvingApp`
// Xcode project that defines the `Shared` module and its test target is created
// in Task 5. Until then, `swift test` cannot run these tests (the repo's
// Package.swift intentionally does not include the app targets). The code and
// tests are written to be self-contained and correct; run them via the Xcode
// project once Task 5 lands.

import Foundation
import SeamCarvingApple
import SeamCarvingCore
import SeamCarvingVision
import XCTest

@testable import Shared

// MARK: - Fake service

struct FakeSeamCarvingService: SeamCarvingService {
    var result: RGBA8Image?
    var shouldThrow: Error?
    var progressReports: [ResizeProgress] = []
    var stall: Bool = false

    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        for progress in progressReports {
            options.progress?(progress)
            // Yield so the model's main-actor progress hop can run and the UI can
            // observe an intermediate `.resizing(progress:)` state.
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        if stall {
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        if let shouldThrow {
            throw shouldThrow
        }
        if let result {
            return result
        }
        return try RGBA8Image.solid(width: target.width, height: target.height, color: RGBA8(r: 0, g: 0, b: 0, a: 255))
    }
}

// MARK: - Helpers

extension ResizeConfigurationTests {
    func makeImage(width: Int, height: Int) throws -> RGBA8Image {
        try RGBA8Image.solid(width: width, height: height, color: RGBA8(r: 128, g: 128, b: 128, a: 255))
    }

    func matchingMask(width: Int, height: Int) throws -> MaskPair {
        let values = [Float](repeating: 0, count: width * height)
        let mask = try Mask(width: width, height: height, values: values)
        let layer = try ProtectionLayer(mask: mask, strength: .hard)
        return try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1_000)
    }

    func mismatchedMask(width: Int, height: Int) throws -> MaskPair {
        let values = [Float](repeating: 0, count: (width + 1) * (height + 1))
        let mask = try Mask(width: width + 1, height: height + 1, values: values)
        let layer = try ProtectionLayer(mask: mask, strength: .hard)
        return try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1_000)
    }

    func sampleFaceConfig(excluded: Set<Int> = []) -> FaceProtectionConfiguration {
        let policy = FaceProtectionPolicy.caireInspired(try! CaireInspiredParameters())
        return FaceProtectionConfiguration(
            policy: policy,
            cadence: .detectOnceAndTransformMask,
            detectedRegions: [try! FaceRegion(x: 0, y: 0, width: 10, height: 10, confidence: 0.9)],
            excludedRegionIndices: excluded
        )
    }
}

// MARK: - Tests

@MainActor
final class ResizeConfigurationTests: XCTestCase {

    // MARK: Document / import

    func testDocumentCarriesSourceAndMasks() throws {
        let image = try makeImage(width: 20, height: 20)
        let doc = ResizeDocument(sourceImage: image, currentMasks: try matchingMask(width: 20, height: 20))
        XCTAssertEqual(doc.sourceSize, try! PixelSize(width: 20, height: 20))
        XCTAssertEqual(doc.targetSize, try! PixelSize(width: 20, height: 20))
    }

    // MARK: Validation

    func testValidatePositiveDimensionsPasses() throws {
        let config = ResizeConfiguration(targetSize: try PixelSize(width: 10, height: 10))
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateZeroDimensionThrows() throws {
        // Zero/negative dimensions are rejected at `PixelSize` construction,
        // which is what `ResizeConfiguration.validate()` relies on.
        XCTAssertThrowsError(try PixelSize(width: 0, height: 10))
    }

    func testValidateNegativeDimensionThrows() throws {
        XCTAssertThrowsError(try PixelSize(width: -5, height: 10))
    }

    func testDocumentMaskMismatchThrows() throws {
        let image = try makeImage(width: 20, height: 20)
        let doc = ResizeDocument(sourceImage: image, currentMasks: try mismatchedMask(width: 20, height: 20))
        XCTAssertThrowsError(try doc.validateMasks())
    }

    func testDocumentMaskMatchPasses() throws {
        let image = try makeImage(width: 20, height: 20)
        let doc = ResizeDocument(sourceImage: image, currentMasks: try matchingMask(width: 20, height: 20))
        XCTAssertNoThrow(try doc.validateMasks())
    }

    func testValidateInvalidFaceConfigThrows() throws {
        let bad = FaceProtectionConfiguration(
            policy: .caireInspired(try! CaireInspiredParameters()),
            detectedRegions: [try! FaceRegion(x: 0, y: 0, width: 10, height: 10, confidence: 0.9)],
            excludedRegionIndices: [5]
        )
        let config = ResizeConfiguration(
            targetSize: try! PixelSize(width: 10, height: 10),
            faceProtection: bad
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case .invalidFaceConfiguration = error as? AppError else {
                XCTFail("expected invalidFaceConfiguration, got \(error)")
                return
            }
        }
    }

    // MARK: Backend selection

    func testAppleSeamCarverConfigurationFromBackend() {
        let config = ResizeConfiguration(
            targetSize: try! PixelSize(width: 10, height: 10),
            backend: .metal,
            deterministic: true
        )
        let appleConfig = AppleSeamCarverConfiguration(
            backend: config.backend,
            metalMode: .full,
            deterministic: config.deterministic
        )
        XCTAssertEqual(appleConfig.backend, .metal)
        XCTAssertTrue(appleConfig.deterministic)
    }

    // MARK: Face configuration

    func testFaceConfigBuildValidateAndExclude() throws {
        var config = sampleFaceConfig()
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.effectiveRegions.count, 1)

        config.excludedRegionIndices = [0]
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.effectiveRegions.count, 0)

        config.excludedRegionIndices = [3]
        XCTAssertThrowsError(try config.validate())
    }

    // MARK: Export failure

    func testExportFailureSetsFailedPhase() async throws {
        let model = AppModel(service: FakeSeamCarvingService())
        model.document = ResizeDocument(sourceImage: try makeImage(width: 20, height: 20))
        model.phase = .ready // not completed -> export should fail
        await model.export()
        if case .failed = model.phase {
            // expected
        } else {
            XCTFail("expected .failed phase, got \(model.phase)")
        }
        XCTAssertNotNil(model.errorMessage)
    }
}
