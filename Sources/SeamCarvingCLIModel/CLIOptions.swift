import Foundation
import SeamCarvingCore

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

/// CLI-neutral face protection request. Platform backends decide whether and
/// how they can satisfy it (Apple maps these cases to Vision policies).
public enum FacePolicyRequest: String, Sendable, Equatable {
    case caire
    case vision
}

public enum FaceCadenceRequest: String, Sendable, Equatable {
    case once
    case eachPass = "each-pass"
}

/// A requested file format, independent of platform encoder APIs.
public enum CLIOutputFormat: String, Sendable, Equatable, Hashable {
    case png
    case jpeg
    case bmp

    public static func parse(_ string: String) -> CLIOutputFormat? {
        switch string.lowercased() {
        case "png": return .png
        case "jpeg", "jpg": return .jpeg
        case "bmp": return .bmp
        default: return nil
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
    public let facePolicy: FacePolicyRequest?
    public let faceCadence: FaceCadenceRequest
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

    public init(
        inputPath: String, outputPath: String, resizeMode: ResizeMode,
        backend: BackendPreference, energy: EnergyMode, dimensionOrder: DimensionOrder,
        preScaleStrategy: PreScaleStrategy, deterministic: Bool,
        protectMaskPath: String?, removeMaskPath: String?, protectStrength: MaskStrength,
        protectWeight: Float, removalWeight: Float, facePolicy: FacePolicyRequest?,
        faceCadence: FaceCadenceRequest, blurRadius: Int?, sobelThreshold: Float?,
        outputFormat: CLIOutputFormat?, debug: Bool, debugDirectory: String?,
        seamColor: SeamColor?, seamShape: SeamShape?, inputDirectory: String?,
        outputDirectory: String?, recursive: Bool, concurrency: Int?
    ) {
        self.inputPath = inputPath; self.outputPath = outputPath; self.resizeMode = resizeMode
        self.backend = backend; self.energy = energy; self.dimensionOrder = dimensionOrder
        self.preScaleStrategy = preScaleStrategy; self.deterministic = deterministic
        self.protectMaskPath = protectMaskPath; self.removeMaskPath = removeMaskPath
        self.protectStrength = protectStrength; self.protectWeight = protectWeight
        self.removalWeight = removalWeight; self.facePolicy = facePolicy; self.faceCadence = faceCadence
        self.blurRadius = blurRadius; self.sobelThreshold = sobelThreshold; self.outputFormat = outputFormat
        self.debug = debug; self.debugDirectory = debugDirectory; self.seamColor = seamColor
        self.seamShape = seamShape; self.inputDirectory = inputDirectory; self.outputDirectory = outputDirectory
        self.recursive = recursive; self.concurrency = concurrency
    }

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

}
