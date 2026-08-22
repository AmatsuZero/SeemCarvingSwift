// ResizeDocument.swift
//
// Document state, kept separate from view state. `ResizeDocument` owns the
// canonical decoded pixels, masks, detected face regions, and export metadata.
// Views must NOT own raw pixel arrays or invoke `SeamEditor` directly; they read
// this model through `AppModel`.

import CoreGraphics
import Foundation
@_spi(Backend) import SeamCarvingCore
import SeamCarvingVision

// MARK: - Resize phase

/// The lifecycle phase of a resize operation, surfaced to the UI as typed state.
public enum ResizePhase: Equatable, Sendable {
    case idle
    case importing
    case ready
    case resizing(progress: ResizeProgress?)
    case cancelled
    case completed
    case failed

    /// A human-readable label for debugging/UI.
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .importing: return "importing"
        case .ready: return "ready"
        case .resizing(let progress):
            if let progress {
                return "resizing \(progress.completedEdits)/\(progress.totalEdits)"
            }
            return "resizing"
        case .cancelled: return "cancelled"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}

// MARK: - Export metadata

/// Lightweight, `Sendable` metadata describing the most recent export.
public struct ExportMetadata: Equatable, Sendable {
    public var exportedAt: Date
    public var byteCount: Int
    public var format: String

    public init(exportedAt: Date = Date(), byteCount: Int = 0, format: String = "png") {
        self.exportedAt = exportedAt
        self.byteCount = byteCount
        self.format = format
    }
}

// MARK: - Resize document

/// The full editable state for one imported image and its resize plan.
///
/// This is owned by the `@MainActor AppModel`, so it is a plain `final class`
/// with mutable members; it is intentionally NOT marked `Sendable` because it is
/// only ever touched on the main actor. It holds the canonical `RGBA8Image` so
/// the model is fully portable and UI-framework-free beyond this Apple module.
public final class ResizeDocument {
    /// The immutable original import. The source is only set on init/re-import
    /// and is never overwritten by a carve. Cancellation returns the document to
    /// a cancelled state *with this source intact*.
    public let sourceImage: RGBA8Image

    /// The current/working image. `nil` until a carve completes; after a
    /// successful resize it holds the carved result. Keeping it separate from
    /// `sourceImage` preserves the original for cancellation semantics.
    public var workingImage: RGBA8Image?

    public var currentMasks: MaskPair
    public var faceRegions: [FaceRegion]?
    public var sourceSize: PixelSize
    public var targetSize: PixelSize
    public var exportMetadata: ExportMetadata?

    public init(
        sourceImage: RGBA8Image,
        currentMasks: MaskPair = .init(),
        faceRegions: [FaceRegion]? = nil,
        targetSize: PixelSize? = nil,
        exportMetadata: ExportMetadata? = nil
    ) {
        self.sourceImage = sourceImage
        self.currentMasks = currentMasks
        self.faceRegions = faceRegions
        self.sourceSize = try! PixelSize(width: sourceImage.width, height: sourceImage.height)
        self.targetSize = targetSize ?? (try! PixelSize(width: sourceImage.width, height: sourceImage.height))
        self.exportMetadata = exportMetadata
    }

    /// Stores a completed carve result into `workingImage` without touching the
    /// immutable `sourceImage`. The source is only reset on re-import.
    public func replaceWorkingImage(_ image: RGBA8Image) {
        self.workingImage = image
    }

    /// Validates that the document's masks match the source image dimensions.
    public func validateMasks() throws {
        try currentMasks.validateDimensions(width: sourceSize.width, height: sourceSize.height)
    }
}
