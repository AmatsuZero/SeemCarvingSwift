// AppModelTests.swift
//
// Behavior tests for the shared `AppModel` (Task 3). They run against a fake
// `SeamCarvingService` (defined in ResizeConfigurationTests.swift, same target)
// so no real carving/Apple frameworks are required.

import Foundation
import SeamCarvingCore
import SeamCarvingVision
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

// MARK: - Task 6/7 GUI capability tests

@MainActor
final class AppModelCaireWorkflowTests: XCTestCase {
    func makeImage(width: Int = 24, height: Int = 20) throws -> RGBA8Image {
        try RGBA8Image.solid(width: width, height: height, color: RGBA8(r: 64, g: 64, b: 64, a: 255))
    }

    func testObjectRemovalRestoreCallsServiceAndKeepsOriginalTargetSize() async throws {
        let image = try makeImage()
        let removal = try Mask(width: image.width, height: image.height, values: [Float](repeating: 1, count: image.width * image.height))
        let masks = try MaskPair(protectionLayers: [], removal: removal, removalWeight: 1_000)
        let recorder = RecordingSeamCarvingService()
        let model = AppModel(service: recorder)
        model.document = ResizeDocument(sourceImage: image, currentMasks: masks, targetSize: try PixelSize(width: 12, height: 20))
        model.configuration.targetSize = try PixelSize(width: 12, height: 20)
        model.configuration.operationMode = .objectRemoval
        model.configuration.restoreOriginalSize = true

        model.resize()
        try await model.waitForTerminalPhase()

        XCTAssertEqual(recorder.lastObjectRemoval?.restoreOriginalSize, true)
        XCTAssertEqual(recorder.lastObjectRemoval?.target, try PixelSize(width: 24, height: 20))
        XCTAssertEqual(model.document?.workingImage?.width, 24)
        XCTAssertEqual(model.document?.workingImage?.height, 20)
        XCTAssertEqual(model.document?.targetSize, try PixelSize(width: 24, height: 20))
    }

    func testFaceDetectionPreflightStoresRegionsAndExclusionsReachResizeService() async throws {
        let image = try makeImage()
        let regions = [
            try FaceRegion(x: 1, y: 2, width: 4, height: 5, confidence: 0.91),
            try FaceRegion(x: 10, y: 3, width: 6, height: 6, confidence: 0.82),
        ]
        let detector = FakeFaceDetector(regions: regions)
        let recorder = RecordingSeamCarvingService()
        let model = AppModel(service: recorder, faceDetector: detector)
        model.document = ResizeDocument(sourceImage: image, targetSize: try PixelSize(width: 18, height: 20))
        model.configuration.targetSize = try PixelSize(width: 18, height: 20)
        model.configuration.faceProtection = FaceProtectionConfiguration(policy: .caireInspired(try CaireInspiredParameters()))

        await model.detectFaces()
        XCTAssertEqual(model.document?.faceRegions, regions)
        XCTAssertEqual(model.configuration.faceProtection?.detectedRegions, regions)
        XCTAssertEqual(model.phase, .ready)

        model.configuration.faceProtection?.excludedRegionIDs = [regions[1].stableID]
        model.resize()
        try await model.waitForTerminalPhase()

        XCTAssertEqual(recorder.lastFaceProtection?.detectedRegions, regions)
        XCTAssertEqual(recorder.lastFaceProtection?.excludedRegionIDs, [regions[1].stableID])
        XCTAssertEqual(recorder.lastFaceProtection?.effectiveRegions, [regions[0]])
    }

    func testFaceDetectionFailureDoesNotDisableProtection() async throws {
        let image = try makeImage()
        let model = AppModel(
            service: RecordingSeamCarvingService(),
            faceDetector: FakeFaceDetector(error: AppError.serviceFailure("vision unavailable"))
        )
        model.document = ResizeDocument(sourceImage: image)
        model.configuration.faceProtection = FaceProtectionConfiguration(policy: .caireInspired(try CaireInspiredParameters()))

        await model.detectFaces()

        XCTAssertNotNil(model.configuration.faceProtection)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertEqual(model.document?.faceRegions, nil)
    }
}


// MARK: - Task 6/7 fake services

final class RecordingSeamCarvingService: SeamCarvingService, @unchecked Sendable {
    struct ObjectRemovalCall: Equatable {
        var restoreOriginalSize: Bool
        var target: PixelSize
    }

    var lastObjectRemoval: ObjectRemovalCall?
    var lastFaceProtection: FaceProtectionConfiguration?

    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        try RGBA8Image.solid(width: target.width, height: target.height, color: RGBA8(r: 0, g: 0, b: 0, a: 255))
    }

    func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        faceProtection: FaceProtectionConfiguration?
    ) async throws -> RGBA8Image {
        lastFaceProtection = faceProtection
        return try await resize(image, to: target, options: options)
    }

    func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        targetMetadata: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image {
        lastObjectRemoval = ObjectRemovalCall(restoreOriginalSize: restoreOriginalSize, target: targetMetadata)
        return try RGBA8Image.solid(
            width: targetMetadata.width,
            height: targetMetadata.height,
            color: RGBA8(r: 0, g: 0, b: 0, a: 255)
        )
    }
}

struct FakeFaceDetector: AppFaceDetecting {
    var regions: [FaceRegion] = []
    var error: Error?

    func detectFaces(in image: RGBA8Image) async throws -> [FaceRegion] {
        if let error { throw error }
        return regions
    }
}

extension AppModel {
    func waitForTerminalPhase(file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            switch phase {
            case .completed, .failed, .cancelled:
                return
            default:
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        XCTFail("Timed out waiting for terminal phase; current phase: \(phase)", file: file, line: line)
    }
}
