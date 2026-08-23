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
