import Foundation
import CoreGraphics
import SeamCarvingCore
import SeamCarvingAppleImaging
import SeamCarvingAppleRuntime
import SeamCarvingVision
import SeamCarvingCLIModel
import SeamCarvingCLIOrchestration

/// Executes the single-image pipeline: read input, build masks, resize via the
/// Apple or face-aware service, then write the result.
///
/// Diagnostics (progress and errors) go to stderr via the injected `progressSink`.
/// The result summary is returned to the caller so binary stdout mode can keep
/// stdout clean; the caller is responsible for printing the summary and mapping
/// thrown errors to `CLIExitCode`.
public struct CLIProcessor: Sendable {
    private let progressSink: @Sendable (ResizeProgress) -> Void
    private let diagnosticSink: @Sendable (String) -> Void

    public init(
        progressSink: @escaping @Sendable (ResizeProgress) -> Void = { progress in
            FileHandle.standardError.write(Data("progress \(progress.completedEdits)/\(progress.totalEdits)\n".utf8))
        },
        diagnosticSink: @escaping @Sendable (String) -> Void = { message in
            FileHandle.standardError.write(Data(message.utf8))
        }
    ) {
        self.progressSink = progressSink
        self.diagnosticSink = diagnosticSink
    }

    public func process(_ options: CLIOptions) async throws -> CLIProcessResult {
        try validateDebugOptions(options)
        try validateReservedOptions(options)
        try validateEnergyControls(options)

        let inputImage = try await CLIImageIO.readImage(fromPath: options.inputPath)
        let sourceSize = try PixelSize(width: inputImage.width, height: inputImage.height)
        let target = try resolveTarget(options.resizeMode, source: sourceSize)
        let masks = try buildMasks(options: options, image: inputImage)
        let debugCollector = options.debug ? SeamObservationCollector() : nil
        let backendPlan = effectiveBackend(for: options)
        if let reason = backendPlan.downgradeReason {
            diagnosticSink("warning: \(reason); using CPU for debug artifacts\n")
        }

        var resizeOptions = ResizeOptions(
            energyMode: options.energy,
            dimensionOrder: options.dimensionOrder,
            masks: masks,
            preScaleStrategy: options.preScaleStrategy,
            blurRadius: options.blurRadius ?? 0,
            sobelThreshold: options.sobelThreshold ?? 0
        )
        resizeOptions.progress = progressSink
        if let debugCollector {
            resizeOptions.seamObserver = { observation in debugCollector.append(observation) }
        }

        let result: CGImage
        if let policy = options.facePolicy {
            let faceCarver = try FaceAwareSeamCarver(
                configuration: AppleSeamCarverConfiguration(
                    backend: backendPlan.effectiveBackend,
                    metalMode: .full,
                    deterministic: options.deterministic || options.debug
                ),
                detector: try VisionFaceDetector(),
                policy: try policy.visionPolicy(),
                cadence: options.faceCadence.visionCadence
            )
            result = try await faceCarver.resize(inputImage, orientation: .up, toPixelSize: target, options: resizeOptions)
        } else {
            let carver = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(
                backend: backendPlan.effectiveBackend,
                deterministic: options.deterministic || options.debug
            ))
            result = try await carver.resize(inputImage, toPixelSize: target, options: resizeOptions)
        }

        let format = try resolveOutputFormat(options)
        try CLIImageIO.writeImage(result, toPath: options.outputPath, format: format)

        if let debugCollector {
            let configuration = try debugConfiguration(options: options, backendPlan: backendPlan)
            try CLIDebugArtifactWriter.write(
                observations: debugCollector.values,
                sourceSize: sourceSize,
                targetSize: target,
                configuration: configuration
            )
        }

        return CLIProcessResult(width: result.width, height: result.height, backend: backendPlan.effectiveBackend)
    }

    /// Rejects blur/Sobel threshold combined with forward energy up front so the
    /// user gets a usage error (exit 64) instead of a backend configuration
    /// error (exit 70).
    private func validateEnergyControls(_ options: CLIOptions) throws {
        if options.energy == .forwardLuma,
           (options.blurRadius ?? 0) > 0 || (options.sobelThreshold ?? 0) > 0 {
            throw CLIConfigurationError.incompatibleOptions(
                "blur radius and Sobel threshold require backward Sobel energy"
            )
        }
    }

    private func resolveTarget(_ mode: ResizeMode, source: PixelSize) throws -> PixelSize {
        switch mode {
        case .exact(let width, let height):
            return try PixelSize(width: width, height: height)
        case .percentage(let percentage):
            return try source.scaled(byPercentage: percentage)
        case .square:
            return source.squareTarget()
        }
    }

    /// Resolves the effective output format: explicit `--format`, otherwise the
    /// output path extension; standard output (`-`) defaults to PNG.
    private func resolveOutputFormat(_ options: CLIOptions) throws -> CLIOutputFormat {
        if let explicit = options.outputFormat {
            return explicit
        }
        if options.outputPath != "-" {
            let ext = (options.outputPath as NSString).pathExtension
            guard let format = CLIOutputFormat.parse(ext) else {
                throw CLIImageIOError.unsupportedOutputFormat(ext)
            }
            return format
        }
        return .png
    }

    private func validateDebugOptions(_ options: CLIOptions) throws {
        if options.debug {
            guard options.debugDirectory != nil else {
                throw CLIConfigurationError.missingRequiredOption("--debug requires --debug-directory")
            }
        } else if options.debugDirectory != nil || options.seamColor != nil || options.seamShape != nil {
            throw CLIConfigurationError.missingRequiredOption(
                "--debug-directory, --seam-color, and --seam-shape require --debug"
            )
        }
    }

    private func effectiveBackend(for options: CLIOptions) -> (effectiveBackend: BackendPreference, downgradeReason: String?) {
        guard options.debug else {
            return (options.backend, nil)
        }
        switch options.backend {
        case .automatic, .metal:
            return (.cpu, "debug artifacts require CPU seam observation")
        case .cpu, .accelerate:
            return (options.backend, nil)
        }
    }

    private func debugConfiguration(
        options: CLIOptions,
        backendPlan: (effectiveBackend: BackendPreference, downgradeReason: String?)
    ) throws -> SeamDebugArtifactConfiguration {
        guard let debugDirectory = options.debugDirectory else {
            throw CLIConfigurationError.missingRequiredOption("--debug requires --debug-directory")
        }
        return SeamDebugArtifactConfiguration(
            directory: URL(fileURLWithPath: debugDirectory),
            color: options.seamColor ?? SeamColor(red: 255, green: 0, blue: 0, alpha: 255),
            shape: options.seamShape ?? .line,
            requestedBackend: options.backend,
            effectiveBackend: backendPlan.effectiveBackend,
            backendDowngradeReason: backendPlan.downgradeReason
        )
    }

    /// Rejects options that are parsed but whose behavior is owned by a later
    /// task. This prevents "flag accepted but silently ignored" behavior: a
    /// reserved flag either does nothing (its default) or fails loudly here.
    private func validateReservedOptions(_ options: CLIOptions) throws {
        if options.inputDirectory != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--input-dir") }
        if options.outputDirectory != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--output-dir") }
        if options.recursive { throw CLIConfigurationError.reservedOptionNotImplemented("--recursive") }
        if options.concurrency != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--concurrency") }
    }

    private func buildMasks(options: CLIOptions, image: CGImage) throws -> MaskPair {
        let inputSize = try PixelSize(width: image.width, height: image.height)
        var masks = MaskPair()
        if let path = options.protectMaskPath {
            let mask = try CLIImageIO.loadMask(path: path)
            guard mask.width == inputSize.width, mask.height == inputSize.height else {
                throw CLIImageIOError.maskDimensionsMismatch(
                    kind: .protection,
                    expected: inputSize,
                    actual: try PixelSize(width: mask.width, height: mask.height)
                )
            }
            masks = try MaskPair(
                protectionLayers: [try ProtectionLayer(mask: mask, strength: options.protectStrength)],
                removal: nil,
                removalWeight: options.removalWeight
            )
        }
        if let path = options.removeMaskPath {
            let mask = try CLIImageIO.loadMask(path: path)
            guard mask.width == inputSize.width, mask.height == inputSize.height else {
                throw CLIImageIOError.maskDimensionsMismatch(
                    kind: .removal,
                    expected: inputSize,
                    actual: try PixelSize(width: mask.width, height: mask.height)
                )
            }
            masks = try MaskPair(
                protectionLayers: masks.protectionLayers,
                removal: mask,
                removalWeight: options.removalWeight
            )
        }
        return masks
    }
}

extension CLIProcessor: CLIImageBackend {
    public var capabilities: CLIBackendCapabilities {
        CLIBackendCapabilities(outputFormats: [.png, .jpeg, .bmp], supportsFaceProtection: true, supportsDebugArtifacts: true)
    }

    public func exitCode(for error: Error) -> CLIExitCode? {
        error is CLIImageIOError ? .dataError : nil
    }

    public func message(for error: Error) -> String? {
        (error as? CLIImageIOError)?.message
    }
}
