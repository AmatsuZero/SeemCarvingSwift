// AppModel.swift
//
// The observable application model. Owns the single resize task, document
// lifecycle, validation, and typed error state. Contains NO image-processing
// logic itself — it delegates carving to a `SeamCarvingService`.

import CoreGraphics
import Foundation
import Observation
import SeamCarvingApple
import SeamCarvingCore
import SeamCarvingVision

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Carving service abstraction

/// The seam-carving boundary the model depends on. Kept as a protocol so tests
/// can inject a fake and so the model stays UI-framework-free of carving details.
public protocol SeamCarvingService: Sendable {
    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image
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
        service: SeamCarvingService = AppleSeamCarverService()
    ) {
        self.configuration = configuration
        self.phase = .idle
        self.service = service
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
        #if canImport(AppKit)
        case .nsImage(let nsImage):
            guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw AppError.serviceFailure("NSImage has no CGImage backing")
            }
            return try CGImageBridge.decode(cgImage)
        #endif
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
        let target = configuration.targetSize
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
                let result = try await activeService.resize(source, to: target, options: options)
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
        document.targetSize = configuration.targetSize
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

    public func export() async {
        guard let document else {
            errorMessage = "No document to export."
            phase = .failed
            return
        }
        // Export is delegated to a platform encoder (Task 4). Here we validate
        // that a completed result exists and record metadata; a real encoder
        // would convert `document.workingImage` (the carve result) to PNG/data.
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
            // Placeholder: encodes to PNG bytes via CGImage bridge when available.
            let _ = try encodePNG(result)
            document.exportMetadata = ExportMetadata(byteCount: 0, format: "png")
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            phase = .failed
        }
    }

    private func encodePNG(_ image: RGBA8Image) throws -> Data {
        #if canImport(CoreGraphics)
        let cgImage = try CGImageBridge.encode(image)
        guard let destination = CGImageDestinationCreateWithData(
            NSMutableData() as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw AppError.serviceFailure("Could not create PNG destination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.serviceFailure("PNG finalization failed")
        }
        return Data()
        #else
        throw AppError.serviceFailure("PNG export requires CoreGraphics")
        #endif
    }
}
