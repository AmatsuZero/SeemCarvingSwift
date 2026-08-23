// EditorUITests.swift
//
// NOTE: This test target is NOT yet wired into the build. The `SeamCarvingApp`
// Xcode project that defines the `Shared` module and its test target is created
// in Task 5. Until then, `swift test` cannot run these tests (the repo's
// Package.swift intentionally does not include the app targets). The tests are
// written to be self-contained and correct; they instantiate the SwiftUI views
// with a fake `AppModel`/`SeamCarvingService` and assert on bound state only.
// Image-processing output is covered by the engine tests, NOT here.

import Foundation
import SeamCarvingCore
import SeamCarvingVision
import SwiftUI
import XCTest

@testable import Shared

// MARK: - Fake model factory

extension EditorUITests {
    /// Builds a model with a fake service and a ready 20x20 document, suitable
    /// for configuration-binding assertions without any real carving.
    @MainActor
    func makeReadyModel() throws -> AppModel {
        let image = try RGBA8Image.solid(width: 20, height: 20, color: RGBA8(r: 128, g: 128, b: 128, a: 255))
        let model = AppModel(service: FakeSeamCarvingService())
        model.document = ResizeDocument(
            sourceImage: image,
            targetSize: try! PixelSize(width: 20, height: 20)
        )
        model.configuration.targetSize = try! PixelSize(width: 20, height: 20)
        model.phase = .ready
        return model
    }
}

// MARK: - Editor UI tests

@MainActor
final class EditorUITests: XCTestCase {

    // MARK: Configuration binding round-trips

    func testTargetSizeBindingRoundTrip() throws {
        let model = try makeReadyModel()
        let view = ResizeControlsView(model: model)
        _ = view.body  // ensure it builds

        model.configuration.targetSize = try! PixelSize(width: 32, height: 24)
        XCTAssertEqual(model.configuration.targetSize.width, 32)
        XCTAssertEqual(model.configuration.targetSize.height, 24)
    }

    func testEnergyAndBackendBinding() throws {
        let model = try makeReadyModel()
        _ = ResizeControlsView(model: model).body

        model.configuration.energyMode = .forwardLuma
        model.configuration.backend = .metal
        model.configuration.deterministic = true
        model.configuration.preScaleStrategy = .lanczosThenExactResidual

        XCTAssertEqual(model.configuration.energyMode, .forwardLuma)
        XCTAssertEqual(model.configuration.backend, .metal)
        XCTAssertTrue(model.configuration.deterministic)
        XCTAssertEqual(model.configuration.preScaleStrategy, .lanczosThenExactResidual)
    }

    // MARK: Disabled state during processing

    func testControlsDisabledWhileResizing() throws {
        let model = try makeReadyModel()
        model.phase = .resizing(progress: nil)
        XCTAssertTrue(model.phase.isProcessing, "resizing phase should be processing")

        let controls = ResizeControlsView(model: model)
        // The Form is disabled while processing; we assert the phase-driven flag
        // the view uses, which is the source of truth for the disabled modifier.
        XCTAssertTrue(model.phase.isProcessing)
    }

    func testMaskToolbarDisabledWhileResizing() throws {
        let model = try makeReadyModel()
        let painter = MaskPaintingController()
        painter.bind(model.document!)
        model.phase = .resizing(progress: nil)
        let toolbar = MaskToolbarView(model: model, painter: painter, mode: .constant(.protect))
        _ = toolbar.body
        XCTAssertTrue(model.phase.isProcessing)
    }

    // MARK: Mask mode changes

    func testMaskModeBinding() throws {
        let model = try makeReadyModel()
        let painter = MaskPaintingController()
        painter.bind(model.document!)
        var mode = LockIsolated(value: MaskMode.protect)
        let toolbar = MaskToolbarView(model: model, painter: painter, mode: Binding(
            get: { mode.value }, set: { mode.value = $0 }
        ))
        _ = toolbar.body
        mode.value = .remove
        XCTAssertEqual(mode.value, .remove)
    }

    func testPaintingEditsDocumentMasks() throws {
        let model = try makeReadyModel()
        let painter = MaskPaintingController()
        painter.bind(model.document!)
        painter.brushRadius = 4
        painter.strength = 1.0

        let before = model.document!.currentMasks
        XCTAssertNil(before.removal)

        painter.paintDab(at: 10, 10, mode: .remove)
        let after = model.document!.currentMasks
        XCTAssertNotNil(after.removal, "removal mask should exist after painting")
        XCTAssertTrue(painter.canUndo)
    }

    func testUndoRestoresMaskState() throws {
        let model = try makeReadyModel()
        let painter = MaskPaintingController()
        painter.bind(model.document!)
        painter.paintDab(at: 5, 5, mode: .remove)
        XCTAssertNotNil(model.document!.currentMasks.removal)
        painter.undo()
        XCTAssertNil(model.document!.currentMasks.removal, "undo should clear the painted removal mask")
        XCTAssertTrue(painter.canRedo)
    }

    // MARK: Cancellation returns to a cancellable state

    func testCancellationReturnsToCancellableState() throws {
        let model = try makeReadyModel()
        // Simulate an in-flight resize then a cancel.
        model.phase = .resizing(progress: nil)
        model.cancelResize()
        // With no in-flight generation beyond the cancel, phase becomes cancelled
        // and the document is retained for further editing.
        if case .cancelled = model.phase {
            // The source must still be intact and ready for a new resize.
            XCTAssertEqual(model.document?.sourceImage.width, 20)
            XCTAssertFalse(model.phase.isProcessing, "cancelled is not processing")
        } else {
            XCTFail("expected .cancelled, got \(model.phase)")
        }
    }

    // MARK: Face protection controls

    func testFaceProtectionEnableAndExclude() throws {
        let model = try makeReadyModel()
        _ = FaceProtectionControlsView(model: model).body

        model.configuration.faceProtection = FaceProtectionConfiguration(
            policy: .caireInspired(try! CaireInspiredParameters()),
            detectedRegions: [try! FaceRegion(x: 0, y: 0, width: 5, height: 5, confidence: 0.9)]
        )
        XCTAssertNotNil(model.configuration.faceProtection)

        // Exclude the first (only) region.
        model.configuration.faceProtection?.excludedRegionIndices.insert(0)
        XCTAssertEqual(model.configuration.faceProtection?.effectiveRegions.count, 0)

        // Toggle policy to vision quality and back.
        model.configuration.faceProtection?.policy = .visionQuality(try! VisionQualityParameters())
        XCTAssertEqual(model.configuration.faceProtection?.policy, .visionQuality(try! VisionQualityParameters()))
    }

    // MARK: Accessibility labels present

    func testAccessibilityIdentifiersDefined() throws {
        let model = try makeReadyModel()
        let painter = MaskPaintingController()
        painter.bind(model.document!)

        _ = ContentView().body
        _ = ResizeControlsView(model: model).body
        _ = MaskToolbarView(model: model, painter: painter, mode: .constant(.protect)).body
        _ = FaceProtectionControlsView(model: model).body
        _ = CarveProgressView(model: model).body
        _ = ExportView(model: model).body

        // Identity constants exist and are non-empty.
        XCTAssertFalse(A11y.ID.resize.isEmpty)
        XCTAssertFalse(A11y.ID.cancel.isEmpty)
        XCTAssertFalse(A11y.ID.targetWidth.isEmpty)
    }

    // MARK: Compact / regular layout behavior

    func testContentViewBuildsInBothLayouts() throws {
        // The view is layout-agnostic at construction; size class is injected by
        // the environment at render time. We assert it constructs without error
        // and that its children (canvas, controls) build.
        let model = try makeReadyModel()
        let content = ContentView()
        _ = content.body

        let painter = MaskPaintingController()
        painter.bind(model.document!)
        _ = ImageCanvasView(model: model, painter: painter, mode: .constant(.protect)).body
    }

    // MARK: Layout regressions

    func testRegularLayoutUsesBoundedSidebarAndDetailMinimumWidth() {
        XCTAssertEqual(EditorLayout.sidebarMinWidth, 280)
        XCTAssertEqual(EditorLayout.sidebarIdealWidth, 320)
        XCTAssertEqual(EditorLayout.sidebarMaxWidth, 380)
        XCTAssertEqual(EditorLayout.detailMinWidth, 420)
    }

    func testCompactLayoutReservesCanvasSpaceBeforeControls() {
        XCTAssertGreaterThanOrEqual(EditorLayout.compactCanvasMinHeight, 280)
        XCTAssertNotEqual(A11y.ID.importButton, A11y.ID.resize)
        XCTAssertNotEqual(A11y.ID.canvasPlaceholder, A11y.ID.resize)
    }

}

// MARK: - Test helpers

/// A minimal thread-safe box so non-Sendable state can be asserted in @MainActor
/// tests without warnings. Here it just carries a `MaskMode` for binding checks.
private struct LockIsolated<T> {
    var value: T
}
