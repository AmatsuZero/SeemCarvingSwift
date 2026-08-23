// AppModel.swift
//
// The observable application model. Owns the single resize task, document
// lifecycle, validation, and typed error state. Contains NO image-processing
// logic itself — it delegates carving to a `SeamCarvingService`.

import CoreGraphics
import Foundation
import ImageIO
import Observation
import SeamCarvingApple
import SeamCarvingCore
import SeamCarvingVision

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

// MARK: - Carving service abstraction

/// The seam-carving boundary the model depends on. Kept as a protocol so tests
/// can inject a fake and so the model stays UI-framework-free of carving details.
public protocol SeamCarvingService: Sendable {
    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image

    /// Dedicated object-removal workflow. Implementations must delegate to the
    /// Core removeObject API rather than treating the removal mask as a normal
    /// resize mask. `targetMetadata` is the size the GUI will show after success
    /// (source size when restoring, resulting carved size otherwise).
    func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        targetMetadata: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image

    /// Optional face-aware entry point. Existing test services retain their
    /// simple implementation through this default forwarding behavior.
    func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        faceProtection: FaceProtectionConfiguration?
    ) async throws -> RGBA8Image
}

public protocol AppFaceDetecting: Sendable {
    func detectFaces(in image: RGBA8Image) async throws -> [FaceRegion]
}

public struct VisionAppFaceDetector: AppFaceDetecting {
    public init() {}

    public func detectFaces(in image: RGBA8Image) async throws -> [FaceRegion] {
        let detector = try VisionFaceDetector()
        let cgImage = try CGImageBridge.encode(image)
        return try await detector.detectFaces(inUpright: cgImage)
    }
}

public enum ExportFormat: String, Sendable, CaseIterable {
    case png
    case jpeg
}

public extension SeamCarvingService {
    func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        targetMetadata: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image {
        var effective = options
        effective.masks = try MaskPair(
            protectionLayers: options.masks.protectionLayers,
            removal: removalMask,
            removalWeight: options.masks.removalWeight
        )
        return try await SeamCarver().removeObject(
            from: image,
            removalMask: removalMask,
            restoreOriginalSize: restoreOriginalSize,
            options: effective
        )
    }

    func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        faceProtection: FaceProtectionConfiguration?
    ) async throws -> RGBA8Image {
        try await resize(image, to: target, options: options)
    }
}

/// Default service wrapping `AppleSeamCarver` (the product's real backend
/// selection). The `backend`/`deterministic` pair is captured at construction so
/// the model can build a correctly-configured instance from `ResizeConfiguration`.
public struct AppleSeamCarverService: SeamCarvingService {
    public var backend: BackendPreference
    public var deterministic: Bool

    public init(backend: BackendPreference = .automatic, deterministic: Bool = false) {
        self.backend = backend
        self.deterministic = deterministic
    }

    public func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        let configuration = AppleSeamCarverConfiguration(
            backend: backend,
            metalMode: .full,
            deterministic: deterministic
        )
        let carver = try AppleSeamCarver(configuration: configuration)
        // The public `AppleSeamCarver` API carves `CGImage`; round-trip the
        // canonical `RGBA8Image` through CoreGraphics (encode -> carve -> decode).
        let sourceCG = try CGImageBridge.encode(image)
        let resultCG = try await carver.resize(sourceCG, toPixelSize: target, options: options)
        return try CGImageBridge.decode(resultCG)
    }

    public func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        targetMetadata: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image {
        var effective = options
        effective.masks = try MaskPair(
            protectionLayers: options.masks.protectionLayers,
            removal: removalMask,
            removalWeight: options.masks.removalWeight
        )
        return try await SeamCarver().removeObject(
            from: image,
            removalMask: removalMask,
            restoreOriginalSize: restoreOriginalSize,
            options: effective
        )
    }

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        faceProtection: FaceProtectionConfiguration?
    ) async throws -> RGBA8Image {
        guard let faceProtection else {
            return try await resize(image, to: target, options: options)
        }

        let sourceCG = try CGImageBridge.encode(image)
        let detector = try VisionFaceDetector()
        let filteredDetector = ExcludingFaceDetector(
            base: detector,
            excludedRegionIDs: faceProtection.excludedRegionIDs,
            excludedRegionIndices: faceProtection.excludedRegionIndices
        )
        let carver = try FaceAwareSeamCarver(
            configuration: AppleSeamCarverConfiguration(
                backend: backend,
                metalMode: .full,
                deterministic: deterministic
            ),
            detector: filteredDetector,
            policy: faceProtection.policy,
            cadence: faceProtection.cadence
        )
        let resultCG = try await carver.resize(
            sourceCG,
            orientation: .up,
            toPixelSize: target,
            options: options
        )
        return try CGImageBridge.decode(resultCG)
    }
}

private struct ExcludingFaceDetector: FaceDetecting, Sendable {
    let base: any FaceDetecting
    let excludedRegionIDs: Set<FaceRegionID>
    let excludedRegionIndices: Set<Int>

    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion] {
        let regions = try await base.detectFaces(inUpright: image)
        return regions.enumerated().compactMap { index, region in
            (excludedRegionIndices.contains(index) || excludedRegionIDs.contains(region.stableID)) ? nil : region
        }
    }
}

// MARK: - App model

/// The central, observable, MainActor-bound application model.
@MainActor
@Observable
public final class AppModel {
    public var document: ResizeDocument?
    public var configuration: ResizeConfiguration
    public var phase: ResizePhase
    public var errorMessage: String?

    /// Injectable service; defaults to the real `AppleSeamCarverService`.
    public var service: SeamCarvingService

    /// Injectable face detector used by the explicit GUI preflight action.
    public var faceDetector: AppFaceDetecting

    /// The single owned resize task. A new `resize()` cancels the prior one.
    private var resizeTask: Task<Void, Never>?

    /// Monotonic generation counter. Each `resize()` mints a new generation; only
    /// the task holding the *current* generation may write a terminal `phase`.
    /// This prevents a stale completion (or a stray cancel) from clobbering a
    /// newer resize's result.
    private var resizeGeneration: UInt64 = 0

    /// The generation owned by `resizeTask`. Lets `cancelResize()` decide whether
    /// it is safe to write `.cancelled` without overwriting a newer completion.
    private var resizeTaskGeneration: UInt64 = 0

    public init(
        configuration: ResizeConfiguration = ResizeConfiguration(),
        service: SeamCarvingService = AppleSeamCarverService(),
        faceDetector: AppFaceDetecting = VisionAppFaceDetector()
    ) {
        self.configuration = configuration
        self.phase = .idle
        self.service = service
        self.faceDetector = faceDetector
    }

    // MARK: Import

    public func importImage(_ source: ImageSource) async {
        phase = .importing
        errorMessage = nil
        do {
            let image = try decode(source)
            let document = ResizeDocument(
                sourceImage: image,
                targetSize: try PixelSize(width: image.width, height: image.height)
            )
            self.document = document
            self.configuration.targetSize = document.targetSize
            self.configuration.faceProtection?.detectedRegions = nil
            phase = .ready
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            phase = .failed
        }
    }

    private func decode(_ source: ImageSource) throws -> RGBA8Image {
        switch source {
        case .cgImage(let cgImage):
            return try CGImageBridge.decode(cgImage)
        #if canImport(UIKit)
        case .uiImage(let uiImage):
            guard let cgImage = uiImage.cgImage else {
                throw AppError.serviceFailure("UIImage has no CGImage backing")
            }
            return try CGImageBridge.decode(cgImage)
        #endif
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        case .nsImage(let nsImage):
            guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw AppError.serviceFailure("NSImage has no CGImage backing")
            }
            return try CGImageBridge.decode(cgImage)
        #endif
        }
    }

    // MARK: Face preflight

    /// Runs explicit face-detection preflight, stores stable region metadata in
    /// the document and face configuration, and leaves face protection enabled on
    /// failure so users can retry or resize without silently losing protection.
    public func detectFaces() async {
        guard let document else {
            errorMessage = "No document imported."
            phase = .failed
            return
        }
        guard configuration.faceProtection != nil else {
            errorMessage = "Enable face protection before detecting faces."
            phase = .failed
            return
        }

        phase = .detectingFaces
        errorMessage = nil
        do {
            let regions = try await faceDetector.detectFaces(in: document.sourceImage)
            document.faceRegions = regions
            // Mutate the observable configuration through a local copy, then assign
            // once. Optional-chained in-place mutations can overlap getter/modify
            // accessors under Swift exclusivity checking.
            if var faceProtection = configuration.faceProtection {
                faceProtection.detectedRegions = regions
                let detectedIDs = Set(regions.map(\.stableID))
                faceProtection.excludedRegionIDs.formIntersection(detectedIDs)
                faceProtection.excludedRegionIndices = faceProtection.excludedRegionIndices.filter {
                    $0 >= 0 && $0 < regions.count
                }
                configuration.faceProtection = faceProtection
            }
            phase = .ready
        } catch {
            errorMessage = "Face detection failed: \(error.localizedDescription)"
            phase = .failed
        }
    }

    // MARK: Resize

    /// Starts a resize and returns immediately. The work runs detached on a
    /// background task; completion/cancellation is observed via `phase`. A newer
    /// `resize()` (or `cancelResize()`) cancels the in-flight task, and only the
    /// most-recently-started task may write a terminal phase.
    public func resize() {
        guard let document else {
            errorMessage = "No document imported."
            phase = .failed
            return
        }

        // Cancel any in-flight resize before starting a new generation.
        resizeTask?.cancel()

        // Validate configuration against the source size and masks.
        do {
            try configuration.validate(against: document.sourceSize)
            try document.validateMasks()
            if configuration.operationMode == .objectRemoval, document.currentMasks.removal == nil {
                throw AppError.missingRemovalMask
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
            return
        }

        // Mint a new generation; only this task may write the terminal phase.
        resizeGeneration &+= 1
        let myGeneration = resizeGeneration
        resizeTaskGeneration = myGeneration

        let source = document.sourceImage
        let target = configuration.operationMode == .objectRemoval && configuration.restoreOriginalSize
            ? document.sourceSize
            : configuration.targetSize
        let faceProtection = configuration.faceProtection
        let options = ResizeOptions(
            energyMode: configuration.energyMode,
            dimensionOrder: configuration.dimensionOrder,
            masks: document.currentMasks,
            preScaleStrategy: configuration.preScaleStrategy,
            progress: { [myGeneration] progress in
                Task { @MainActor in
                    // Ignore progress from a stale or superseded generation.
                    guard myGeneration == self.resizeGeneration, case .resizing = self.phase else { return }
                    self.phase = .resizing(progress: progress)
                }
            }
        )

        phase = .resizing(progress: nil)
        errorMessage = nil

        // Use the injected service. When it is the default real service, rebuild
        // it from the current configuration so backend/deterministic settings are
        // honored; test fakes (a different concrete type) are used as-is.
        let activeService: SeamCarvingService = (service as? AppleSeamCarverService).map {
            _ in AppleSeamCarverService(backend: configuration.backend, deterministic: configuration.deterministic)
        } ?? service

        resizeTask = Task { [weak self] in
            do {
                let result: RGBA8Image
                if self?.configuration.operationMode == .objectRemoval, let removal = document.currentMasks.removal {
                    result = try await activeService.removeObject(
                        from: source,
                        removalMask: removal,
                        restoreOriginalSize: self?.configuration.restoreOriginalSize ?? true,
                        targetMetadata: target,
                        options: options
                    )
                } else {
                    result = try await activeService.resize(
                        source,
                        to: target,
                        options: options,
                        faceProtection: faceProtection
                    )
                }
                try Task.checkCancellation()
                await self?.applyResult(result, generation: myGeneration)
            } catch is CancellationError {
                await self?.handleCancellation(generation: myGeneration)
            } catch {
                await self?.handleFailure(error, generation: myGeneration)
            }
        }
    }

    private func applyResult(_ result: RGBA8Image, generation: UInt64) async {
        // Only the current generation may write the completed terminal phase.
        guard generation == resizeGeneration else { return }
        guard let document else { return }
        document.replaceWorkingImage(result)
        document.targetSize = (try? PixelSize(width: result.width, height: result.height)) ?? configuration.targetSize
        phase = .completed
        errorMessage = nil
    }

    private func handleCancellation(generation: UInt64) async {
        // Only the current generation may write the cancelled terminal phase; this
        // prevents a stale task from clobbering a newer completion. The source image
        // is retained untouched, so the document returns to a cancelled state.
        guard generation == resizeGeneration else { return }
        phase = .cancelled
        errorMessage = nil
    }

    private func handleFailure(_ error: Error, generation: UInt64) async {
        // Only the current generation may write the failed terminal phase.
        guard generation == resizeGeneration else { return }
        errorMessage = error.localizedDescription
        phase = .failed
    }

    public func cancelResize() {
        resizeTask?.cancel()
        resizeTask = nil
        // Only set `.cancelled` if the task we just cancelled is still the current
        // generation. If a newer `resize()` is running (or already completed), its
        // result owns the phase and we must not clobber it.
        guard resizeTaskGeneration == resizeGeneration else { return }
        phase = .cancelled
        errorMessage = nil
    }

    // MARK: Export

    public func export(format: ExportFormat = .png) async {
        guard let document else {
            errorMessage = "No document to export."
            phase = .failed
            return
        }
        // The immutable `sourceImage` is NOT the export artifact.
        guard phase == .completed else {
            errorMessage = "Nothing to export; run a resize first."
            phase = .failed
            return
        }
        guard let result = document.workingImage else {
            errorMessage = "Nothing to export; run a resize first."
            phase = .failed
            return
        }
        do {
            let data = try encode(result, format: format)
            document.exportedData = data
            document.exportMetadata = ExportMetadata(byteCount: data.count, format: format.rawValue)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            phase = .failed
        }
    }

    private func encode(_ image: RGBA8Image, format: ExportFormat) throws -> Data {
        #if canImport(CoreGraphics)
        let cgImage = try CGImageBridge.encode(image)
        let mutableData = NSMutableData()
        let type = format == .png ? "public.png" : "public.jpeg"
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            type as CFString,
            1,
            nil
        ) else {
            throw AppError.serviceFailure("Could not create export destination")
        }
        let properties: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.serviceFailure("Export finalization failed")
        }
        return mutableData as Data
        #else
        throw AppError.serviceFailure("Image export requires CoreGraphics")
        #endif
    }
}
