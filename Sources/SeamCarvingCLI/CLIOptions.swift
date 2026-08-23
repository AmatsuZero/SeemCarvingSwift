import Foundation
import SeamCarvingCore
import SeamCarvingVision

public enum CLIParseError: Error, Equatable {
    case invalidArguments
    case conflictingModes

    public var message: String {
        switch self {
        case .invalidArguments: return "invalid arguments"
        case .conflictingModes: return "conflicting resize modes"
        }
    }
}

/// Parsed command-line options for `seamcarve-cli`.
///
/// The positional `INPUT OUTPUT --width PIXELS --height PIXELS` syntax is
/// stable. Fields marked "reserved" freeze the future CLI surface: they are
/// parsed and validated here but wired into the engine in later tasks.
public struct CLIOptions: Sendable, Equatable {
    public let inputPath: String
    public let outputPath: String
    public let resizeMode: ResizeMode
    public let backend: BackendPreference
    public let energy: EnergyMode
    public let dimensionOrder: DimensionOrder
    public let preScaleStrategy: PreScaleStrategy
    public let deterministic: Bool
    public let protectMaskPath: String?
    public let removeMaskPath: String?
    public let protectStrength: MaskStrength
    public let protectWeight: Float
    public let removalWeight: Float
    public let facePolicy: FaceProtectionPolicy?
    public let faceCadence: FaceDetectionCadence
    /// Box-blur radius applied to luma before backward Sobel energy (`--blur-radius`).
    public let blurRadius: Int?
    /// Sobel gradient-magnitude threshold for backward energy (`--sobel-threshold`).
    public let sobelThreshold: Float?
    /// Explicit output format (`--format png|jpeg|bmp`), overriding extension detection.
    public let outputFormat: CLIOutputFormat?
    /// Enables seam/debug sidecar artifacts.
    public let debug: Bool
    /// Directory for debug artifacts. Required when `debug` is true.
    public let debugDirectory: String?
    /// Seam overlay color.
    public let seamColor: SeamColor?
    /// Seam visualization shape.
    public let seamShape: SeamShape?
    /// Reserved: batch input directory.
    public let inputDirectory: String?
    /// Reserved: batch output directory.
    public let outputDirectory: String?
    /// Reserved: recurse into the batch input directory.
    public let recursive: Bool
    /// Reserved: batch concurrency limit.
    public let concurrency: Int?

    /// Target width for the `exact` resize mode, or `nil` for other modes.
    ///
    /// Provided for source compatibility with the pre-`ResizeMode` API. New
    /// callers should read `resizeMode` directly.
    public var width: Int? {
        if case .exact(let width, _) = resizeMode { return width }
        return nil
    }

    /// Target height for the `exact` resize mode, or `nil` for other modes.
    ///
    /// Provided for source compatibility with the pre-`ResizeMode` API. New
    /// callers should read `resizeMode` directly.
    public var height: Int? {
        if case .exact(_, let height) = resizeMode { return height }
        return nil
    }

    /// Parses argv-style command line arguments into typed business options.
    ///
    /// This test seam intentionally remains available after migrating syntax
    /// parsing to swift-argument-parser so callers and tests do not need to
    /// spawn the executable to verify argv-to-options behavior.
    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        try CLIArgumentParser.parseOptions(arguments)
    }

}
