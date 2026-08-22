// AppModelTests.swift
//
// Behavior tests for the shared `AppModel` (Task 3). They run against a fake
// `SeamCarvingService` (defined in ResizeConfigurationTests.swift, same target)
// so no real carving/Apple frameworks are required.

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

        let resizeTask = Task { model.resize() }
        // Let it enter the resizing phase.
        try await Task.sleep(nanoseconds: 50_000_000)
        model.cancelResize()

        await resizeTask.value

        XCTAssertEqual(model.phase, .cancelled, "phase should be cancelled after cancel")
        // The immutable source must be untouched by a carve or cancellation.
        XCTAssertEqual(model.document?.sourceImage.width, 40)
        XCTAssertEqual(model.document?.sourceImage.height, 40, "source image must be retained intact")
        // No working result should exist after cancellation.
        XCTAssertNil(model.document?.workingImage, "cancellation must not leave a working image")
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

        // `resize()` is non-blocking; poll the main-actor phase for an
        // intermediate `.resizing(progress:)` observation, not just `.completed`.
        model.resize()

        var sawProgress = false
        for _ in 0..<200 {
            if case .resizing(let p) = model.phase, p != nil {
                sawProgress = true
            }
            if case .completed = model.phase { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertTrue(sawProgress, "phase should have shown an intermediate .resizing(progress:) state")
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

        model.resize()

        // Wait for the detached task to write the terminal phase.
        for _ in 0..<200 {
            if case .failed = model.phase { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

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
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)

        model.resize()

        // Validation failure is synchronous within `resize()`, but poll to be safe.
        for _ in 0..<200 {
            if case .failed = model.phase { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        if case .failed = model.phase {
            // expected
        } else {
            XCTFail("expected .failed for invalid mask, got \(model.phase)")
        }
    }

    // MARK: Newer resize supersedes a stale completion

    func testNewerResizeSupersedesStaleCompletion() async throws {
        let image = try makeImage(width: 40, height: 40)
        // First resize stalls; second completes. The stale cancel/completion of the
        // first must not clobber the second's `.completed`.
        let model = AppModel(service: FakeSeamCarvingService(stall: true))
        model.document = ResizeDocument(
            sourceImage: image,
            targetSize: try! PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)

        model.resize()
        try await Task.sleep(nanoseconds: 30_000_000)
        // Cancel the first (stale) generation.
        model.cancelResize()
        // Start a second generation that completes immediately.
        model.service = FakeSeamCarvingService()
        model.resize()

        for _ in 0..<200 {
            if case .completed = model.phase { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(model.phase, .completed, "newer resize must win, stale cancel must not clobber")
        XCTAssertEqual(model.document?.sourceImage.width, 40, "source retained across supersede")
        XCTAssertNotNil(model.document?.workingImage, "working image should hold the carved result")
    }
}
