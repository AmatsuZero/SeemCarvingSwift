import Foundation
import CoreGraphics
import SeamCarvingCore
import SeamCarvingApple
import SeamCarvingVision

/// The result of a single-image CLI run.
public struct CLIProcessResult: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let backend: BackendPreference

    public init(width: Int, height: Int, backend: BackendPreference) {
        self.width = width
        self.height = height
        self.backend = backend
    }
}

/// Executes the single-image pipeline: read input, build masks, resize via the
/// Apple or face-aware service, then write the result.
///
/// Diagnostics (progress and errors) go to stderr via the injected `progressSink`.
/// The result summary is returned to the caller so binary stdout mode can keep
/// stdout clean; the caller is responsible for printing the summary and mapping
/// thrown errors to `CLIExitCode`.
public struct CLIProcessor: Sendable {
    private let progressSink: @Sendable (ResizeProgress) -> Void

    public init(
        progressSink: @escaping @Sendable (ResizeProgress) -> Void = { progress in
            FileHandle.standardError.write(Data("progress \(progress.completedEdits)/\(progress.totalEdits)\n".utf8))
        }
    ) {
        self.progressSink = progressSink
    }

    public func process(_ options: CLIOptions) async throws -> CLIProcessResult {
        try validateReservedOptions(options)
        try validateEnergyControls(options)

        let inputImage = try await CLIImageIO.readImage(fromPath: options.inputPath)
        let sourceSize = try PixelSize(width: inputImage.width, height: inputImage.height)
        let target = try resolveTarget(options.resizeMode, source: sourceSize)
        let masks = try buildMasks(options: options, image: inputImage)

        var resizeOptions = ResizeOptions(
            energyMode: options.energy,
            dimensionOrder: options.dimensionOrder,
            masks: masks,
            preScaleStrategy: options.preScaleStrategy,
            blurRadius: options.blurRadius ?? 0,
            sobelThreshold: options.sobelThreshold ?? 0
        )
        resizeOptions.progress = progressSink

        let result: CGImage
        if let policy = options.facePolicy {
            let faceCarver = try FaceAwareSeamCarver(
                configuration: AppleSeamCarverConfiguration(
                    backend: options.backend,
                    metalMode: .full,
                    deterministic: options.deterministic
                ),
                detector: try VisionFaceDetector(),
                policy: policy,
                cadence: options.faceCadence
            )
            result = try await faceCarver.resize(inputImage, orientation: .up, toPixelSize: target, options: resizeOptions)
        } else {
            let carver = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(
                backend: options.backend,
                deterministic: options.deterministic
            ))
            result = try await carver.resize(inputImage, toPixelSize: target, options: resizeOptions)
        }

        let format = try resolveOutputFormat(options)
        try CLIImageIO.writeImage(result, toPath: options.outputPath, format: format)

        return CLIProcessResult(width: result.width, height: result.height, backend: options.backend)
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

    /// Rejects options that are parsed but whose behavior is owned by a later
    /// task. This prevents "flag accepted but silently ignored" behavior: a
    /// reserved flag either does nothing (its default) or fails loudly here.
    private func validateReservedOptions(_ options: CLIOptions) throws {
        if options.debug { throw CLIConfigurationError.reservedOptionNotImplemented("--debug") }
        if options.debugDirectory != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--debug-directory") }
        if options.seamColor != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--seam-color") }
        if options.seamShape != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--seam-shape") }
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
