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
/// Diagnostics (progress and errors) go to stderr. The result summary is
/// returned to the caller so a future binary stdout mode can keep stdout clean;
/// the caller is responsible for printing the summary and mapping thrown errors
/// to `CLIExitCode`.
public struct CLIProcessor: Sendable {
    public init() {}

    public func process(_ options: CLIOptions) async throws -> CLIProcessResult {
        try validateReservedOptions(options)
        let target = try resolveTarget(options.resizeMode)

        let inputImage = try CLIImageIO.readImage(fromPath: options.inputPath)
        let masks = try buildMasks(options: options, image: inputImage)

        var resizeOptions = ResizeOptions(
            energyMode: options.energy,
            dimensionOrder: options.dimensionOrder,
            masks: masks,
            preScaleStrategy: options.preScaleStrategy
        )
        resizeOptions.progress = { progress in
            FileHandle.standardError.write(Data("progress \(progress.completedEdits)/\(progress.totalEdits)\n".utf8))
        }

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

        try CLIImageIO.writeImage(result, toPath: options.outputPath)

        return CLIProcessResult(width: result.width, height: result.height, backend: options.backend)
    }

    private func resolveTarget(_ mode: ResizeMode) throws -> PixelSize {
        switch mode {
        case .exact(let width, let height):
            return try PixelSize(width: width, height: height)
        case .percentage, .square:
            throw CLIConfigurationError.reservedResizeModeNotImplemented(mode)
        }
    }

    /// Rejects options that are parsed but whose behavior is owned by a later
    /// task. This prevents "flag accepted but silently ignored" behavior: a
    /// reserved flag either does nothing (its default) or fails loudly here.
    private func validateReservedOptions(_ options: CLIOptions) throws {
        if options.blurRadius != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--blur-radius") }
        if options.sobelThreshold != nil { throw CLIConfigurationError.reservedOptionNotImplemented("--sobel-threshold") }
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
