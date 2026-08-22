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

    public func resize() async {
        guard let document else {
            errorMessage = "No document imported."
            phase = .failed
            return
        }

        // Cancel any in-flight resize before starting a new one.
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

        let source = document.sourceImage
        let target = configuration.targetSize
        let options = ResizeOptions(
            energyMode: configuration.energyMode,
            dimensionOrder: configuration.dimensionOrder,
            masks: document.currentMasks,
            preScaleStrategy: configuration.preScaleStrategy,
            progress: { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .resizing = self.phase else { return }
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

        let task = Task {
            do {
                let result = try await activeService.resize(source, to: target, options: options)
                try Task.checkCancellation()
                await self.applyResult(result)
            } catch is CancellationError {
                await self.handleCancellation()
            } catch {
                await self.handleFailure(error)
            }
        }
        resizeTask = task
        await task.value
    }

    private func applyResult(_ result: RGBA8Image) async {
        guard let document else { return }
        document.replaceWorkingImage(result)
        document.targetSize = configuration.targetSize
        phase = .completed
        errorMessage = nil
    }

    private func handleCancellation() async {
        // Source image is retained untouched; return to a cancelled state.
        phase = .cancelled
        errorMessage = nil
    }

    private func handleFailure(_ error: Error) async {
        errorMessage = error.localizedDescription
        phase = .failed
    }

    public func cancelResize() {
        resizeTask?.cancel()
        resizeTask = nil
        // Source image remains intact; document is not mutated.
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
        // would convert `document.sourceImage` to PNG/data. We fail cleanly if
        // no completed result is present or the encoder throws.
        guard phase == .completed else {
            errorMessage = "Nothing to export; run a resize first."
            phase = .failed
            return
        }
        do {
            // Placeholder: encodes to PNG bytes via CGImage bridge when available.
            let _ = try encodePNG(document.sourceImage)
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
