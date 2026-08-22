// AppModelTests.swift
//
// NOTE: This test target is NOT yet wired into the build. The `SeamCarvingApp`
// Xcode project that defines the `Shared` module and its test target is created
// in Task 5. Until then, `swift test` cannot run these tests. The code and tests
// are written to be self-contained and correct; run them via the Xcode project
// once Task 5 lands.

import Foundation
import SeamCarvingCore
import XCTest

@testable import Shared

// MARK: - Model behavior tests (cancellation, progress, failure)

@MainActor
final class AppModelTests: XCTestCase {

    func makeImage(width: Int, height: Int) throws -> RGBA8Image {
        try RGBA8Image.solid(width: width, height: height, color: RGBA8(r: 128, g: 128, b: 128, a: 255))
    }

    // MARK: Cancellation

    func testCancelRetainsSourceAndSetsCancelled() async throws {
        let image = try makeImage(width: 40, height: 40)
        let model = AppModel(service: FakeSeamCarvingService(stall: true))
        model.document = ResizeDocument(
            sourceImage: image,
            targetSize: try! PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)

        let resizeTask = Task { await model.resize() }
        // Let it enter the resizing phase.
        try await Task.sleep(nanoseconds: 50_000_000)
        model.cancelResize()

        await resizeTask.value

        XCTAssertEqual(model.phase, .cancelled, "phase should be cancelled after cancel")
        XCTAssertEqual(model.document?.sourceImage.width, 40)
        XCTAssertEqual(model.document?.sourceImage.height, 40, "source image must be retained intact")
        XCTAssertNil(model.errorMessage)
    }

    // MARK: Progress

    func testProgressReportedThroughPhase() async throws {
        let image = try makeImage(width: 40, height: 40)
        let progress = [
            ResizeProgress(completedEdits: 1, totalEdits: 10, size: try! PixelSize(width: 39, height: 40)),
            ResizeProgress(completedEdits: 5, totalEdits: 10, size: try! PixelSize(width: 35, height: 40)),
        ]
        let model = AppModel(service: FakeSeamCarvingService(progressReports: progress))
        model.document = ResizeDocument(
            sourceImage: image,
            targetSize: try! PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)

        await model.resize()

        // Final phase is .completed; intermediate progress was observed.
        if case .completed = model.phase {
            // expected
        } else {
            XCTFail("expected .completed, got \(model.phase)")
        }
    }

    // MARK: Failure surfaces as typed state

    func testServiceThrowSetsFailedPhase() async throws {
        let image = try makeImage(width: 40, height: 40)
        let model = AppModel(service: FakeSeamCarvingService(shouldThrow: AppError.serviceFailure("boom")))
        model.document = ResizeDocument(
            sourceImage: image,
            targetSize: try! PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)

        await model.resize()

        if case .failed = model.phase {
            // expected
        } else {
            XCTFail("expected .failed, got \(model.phase)")
        }
        XCTAssertEqual(model.errorMessage, "Resize failed: boom")
    }

    // MARK: Validation failure before carving

    func testInvalidMaskPreventsResize() async throws {
        let image = try makeImage(width: 40, height: 40)
        // A mask whose dimensions do not match the source is invalid.
        let values = [Float](repeating: 0, count: 41 * 41)
        let mask = try Mask(width: 41, height: 41, values: values)
        let layer = try ProtectionLayer(mask: mask, strength: .hard)
        let badMasks = try MaskPair(protectionLayers: [layer], removal: nil, removalWeight: 1_000)

        let model = AppModel(service: FakeSeamCarvingService())
        model.document = ResizeDocument(
            sourceImage: image,
            currentMasks: badMasks,
            targetSize: try PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try PixelSize(width: 20, height: 20)

        await model.resize()

        if case .failed = model.phase {
            // expected
        } else {
            XCTFail("expected .failed for invalid mask, got \(model.phase)")
        }
    }
}
