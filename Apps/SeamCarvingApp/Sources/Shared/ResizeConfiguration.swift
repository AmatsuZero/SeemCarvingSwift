// ResizeConfiguration.swift
//
// Shared, UI-framework-free (apart from Apple-only CoreGraphics) configuration
// model for the Seam Carving app. Defines the persisted resize settings
// (`ResizeConfiguration`), the face-protection wrapper (`FaceProtectionConfiguration`),
// the import source carrier (`ImageSource`), and the typed validation error
// (`AppError`). No image-processing logic lives here.

import CoreGraphics
import Foundation
import SeamCarvingCore
import SeamCarvingVision

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension PixelSize {
    /// A valid 1×1 size usable as a non-throwing default argument.
    @usableFromInline
    static let unit = try! PixelSize(width: 1, height: 1)
}

/// Builds the default 1×1 target size without raising in a default argument.
@usableFromInline
func defaultTargetSize() -> PixelSize { .unit }

// MARK: - Typed application errors

/// Errors surfaced to the UI as typed state (`errorMessage` / `phase = .failed`).
/// We never use `fatalError` for user-facing configuration problems. Conforms to
/// `LocalizedError` so `error.localizedDescription` yields a friendly message.
public enum AppError: Error, Equatable, LocalizedError {
    case invalidTargetDimensions
    case maskDimensionMismatch
    case invalidFaceConfiguration(String)
    case backendUnsupported(BackendPreference)
    case serviceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTargetDimensions:
            return "Target width and height must be positive."
        case .maskDimensionMismatch:
            return "Protection or removal mask dimensions must match the source image."
        case .invalidFaceConfiguration(let reason):
            return "Face protection is invalid: \(reason)"
        case .backendUnsupported(let backend):
            return "Backend '\(backend)' is not available on this device."
        case .serviceFailure(let reason):
            return "Resize failed: \(reason)"
        }
    }
}

// MARK: - Import source

/// A decoded image to be imported into the resize document.
///
/// `CGImage` is Apple-only; this shared module targets macOS/iOS so referencing
/// it directly is fine here. The raw pixel array is extracted into an
/// `RGBA8Image` by the importer (see `AppModel.importImage`), keeping views and
/// documents free of platform image types.
///
/// `CGImage`/`UIImage`/`NSImage` are not themselves `Equatable`, so equality is
/// defined by reference identity (sufficient for UI state comparisons).
public enum ImageSource: Sendable {
    case cgImage(CGImage)
    #if canImport(UIKit)
    case uiImage(UIImage)
    #endif
    #if canImport(AppKit)
    case nsImage(NSImage)
    #endif

    public static func == (lhs: ImageSource, rhs: ImageSource) -> Bool {
        switch (lhs, rhs) {
        case (.cgImage(let a), .cgImage(let b)):
            return a === b
        #if canImport(UIKit)
        case (.uiImage(let a), .uiImage(let b)):
            return a === b
        #endif
        #if canImport(AppKit)
        case (.nsImage(let a), .nsImage(let b)):
            return a === b
        #endif
        default:
            return false
        }
    }
}

// MARK: - Face protection configuration

/// The UI's face-protection settings: the policy + cadence, plus the detected
/// regions and any user-excluded region indices. A user can drop an unwanted
/// detected face from protection (Task 4) by adding its index to
/// `excludedRegionIndices`.
public struct FaceProtectionConfiguration: Equatable, Sendable {
    public var policy: FaceProtectionPolicy
    public var cadence: FaceDetectionCadence
    public var detectedRegions: [FaceRegion]?
    public var excludedRegionIndices: Set<Int>

    public init(
        policy: FaceProtectionPolicy,
        cadence: FaceDetectionCadence = .detectOnceAndTransformMask,
        detectedRegions: [FaceRegion]? = nil,
        excludedRegionIndices: Set<Int> = []
    ) {
        self.policy = policy
        self.cadence = cadence
        self.detectedRegions = detectedRegions
        self.excludedRegionIndices = excludedRegionIndices
    }

    /// Regions that should actually be protected (detected minus excluded).
    public var effectiveRegions: [FaceRegion] {
        guard let detected = detectedRegions else { return [] }
        return detected.enumerated().compactMap { index, region in
            excludedRegionIndices.contains(index) ? nil : region
        }
    }

    /// Validates that excluded indices are within the detected regions (when
    /// regions are present) so the UI cannot reference phantom indices.
    public func validate() throws {
        if let detected = detectedRegions {
            for index in excludedRegionIndices where index < 0 || index >= detected.count {
                throw AppError.invalidFaceConfiguration(
                    "excluded region index \(index) out of range 0..<\(detected.count)"
                )
            }
        }
    }
}

// MARK: - Resize configuration

/// The persisted, validated settings for a resize operation.
public struct ResizeConfiguration: Equatable, Sendable {
    public var targetSize: PixelSize
    public var energyMode: EnergyMode
    public var dimensionOrder: DimensionOrder
    public var backend: BackendPreference
    public var deterministic: Bool
    public var preScaleStrategy: PreScaleStrategy
    public var faceProtection: FaceProtectionConfiguration?

    public init(
        targetSize: PixelSize = defaultTargetSize(),
        energyMode: EnergyMode = .backwardSobel,
        dimensionOrder: DimensionOrder = .widthThenHeight,
        backend: BackendPreference = .automatic,
        deterministic: Bool = false,
        preScaleStrategy: PreScaleStrategy = .none,
        faceProtection: FaceProtectionConfiguration? = nil
    ) {
        self.targetSize = targetSize
        self.energyMode = energyMode
        self.dimensionOrder = dimensionOrder
        self.backend = backend
        self.deterministic = deterministic
        self.preScaleStrategy = preScaleStrategy
        self.faceProtection = faceProtection
    }

    /// Validates dimensions and nested configuration without a known source size.
    public func validate() throws {
        guard targetSize.width > 0, targetSize.height > 0 else {
            throw AppError.invalidTargetDimensions
        }
        if let face = faceProtection {
            try face.validate()
        }
    }

    /// Validates against a concrete source size, including mask-dimension
    /// matching (delegated to `MaskPair.validateDimensions` by the caller via
    /// `ResizeDocument`). Here we check that the target is not larger than the
    /// source in a way the carver rejects and that face config is valid.
    public func validate(against sourceSize: PixelSize) throws {
        try validate()
        guard targetSize.width > 0, targetSize.height > 0 else {
            throw AppError.invalidTargetDimensions
        }
        // The carver can shrink or enlarge; it only requires positive dims. We
        // additionally guard against the degenerate equal-to-source no-op being
        // treated as an error elsewhere. Nothing to reject here beyond positivity.
        if let face = faceProtection {
            try face.validate()
        }
    }
}
