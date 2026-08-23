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
    /// Reserved: blur radius applied before energy computation.
    public let blurRadius: Float?
    /// Reserved: Sobel threshold for energy computation.
    public let sobelThreshold: Float?
    /// Reserved: enable seam/debug artifacts.
    public let debug: Bool
    /// Reserved: directory for debug artifacts.
    public let debugDirectory: String?
    /// Reserved: seam overlay color.
    public let seamColor: SeamColor?
    /// Reserved: seam visualization shape.
    public let seamShape: SeamShape?
    /// Reserved: batch input directory.
    public let inputDirectory: String?
    /// Reserved: batch output directory.
    public let outputDirectory: String?
    /// Reserved: recurse into the batch input directory.
    public let recursive: Bool
    /// Reserved: batch concurrency limit.
    public let concurrency: Int?

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var inputPath: String?
        var outputPath: String?
        var width: Int?
        var height: Int?
        var percentage: Float?
        var square = false
        var backend = BackendPreference.automatic
        var energy = EnergyMode.backwardSobel
        var dimensionOrder = DimensionOrder.widthThenHeight
        var preScaleStrategy = PreScaleStrategy.none
        var deterministic = false
        var protectMaskPath: String?
        var removeMaskPath: String?
        var protectStrength = MaskStrength.soft(1_000)
        var protectWeight: Float = 1_000
        var removalWeight: Float = 1_000
        var facePolicy: FaceProtectionPolicy?
        var faceCadence = FaceDetectionCadence.detectOnceAndTransformMask
        var blurRadius: Float?
        var sobelThreshold: Float?
        var debug = false
        var debugDirectory: String?
        var seamColor: SeamColor?
        var seamShape: SeamShape?
        var inputDirectory: String?
        var outputDirectory: String?
        var recursive = false
        var concurrency: Int?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--width":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    throw CLIParseError.invalidArguments
                }
                width = value
                index += 2
            case "--height":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    throw CLIParseError.invalidArguments
                }
                height = value
                index += 2
            case "--percentage":
                guard index + 1 < arguments.count, let value = parsePositiveFloat(arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                percentage = value
                index += 2
            case "--square":
                square = true
                index += 1
            case "--backend":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                backend = try parseBackend(arguments[index + 1])
                index += 2
            case "--energy":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                energy = try parseEnergy(arguments[index + 1])
                index += 2
            case "--order":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                dimensionOrder = try parseDimensionOrder(arguments[index + 1])
                index += 2
            case "--pre-scale":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                preScaleStrategy = try parsePreScale(arguments[index + 1])
                index += 2
            case "--deterministic":
                deterministic = true
                index += 1
            case "--protect-mask":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                protectMaskPath = arguments[index + 1]
                index += 2
            case "--remove-mask":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                removeMaskPath = arguments[index + 1]
                index += 2
            case "--protect-strength":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                switch arguments[index + 1] {
                case "hard": protectStrength = .hard
                case "soft": protectStrength = .soft(protectWeight)
                default: throw CLIParseError.invalidArguments
                }
                index += 2
            case "--protect-weight":
                guard index + 1 < arguments.count, let value = parseNonNegativeFloat(arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                protectWeight = value
                if case .soft = protectStrength { protectStrength = .soft(value) }
                index += 2
            case "--removal-weight":
                guard index + 1 < arguments.count, let value = parseNonNegativeFloat(arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                removalWeight = value
                index += 2
            case "--face-policy":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                facePolicy = try parseFacePolicy(arguments[index + 1])
                index += 2
            case "--face-cadence":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                switch arguments[index + 1] {
                case "once": faceCadence = .detectOnceAndTransformMask
                case "each-pass": faceCadence = .redetectEveryPass
                default: throw CLIParseError.invalidArguments
                }
                index += 2
            case "--blur-radius":
                guard index + 1 < arguments.count, let value = parseNonNegativeFloat(arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                blurRadius = value
                index += 2
            case "--sobel-threshold":
                guard index + 1 < arguments.count, let value = parseNonNegativeFloat(arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                sobelThreshold = value
                index += 2
            case "--debug":
                debug = true
                index += 1
            case "--debug-directory":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                debugDirectory = arguments[index + 1]
                index += 2
            case "--seam-color":
                guard index + 1 < arguments.count, let value = SeamColor(hexString: arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                seamColor = value
                index += 2
            case "--seam-shape":
                guard index + 1 < arguments.count, let value = SeamShape(rawValue: arguments[index + 1]) else {
                    throw CLIParseError.invalidArguments
                }
                seamShape = value
                index += 2
            case "--input-dir":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                inputDirectory = arguments[index + 1]
                index += 2
            case "--output-dir":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                outputDirectory = arguments[index + 1]
                index += 2
            case "--recursive":
                recursive = true
                index += 1
            case "--concurrency":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    throw CLIParseError.invalidArguments
                }
                concurrency = value
                index += 2
            default:
                guard !argument.hasPrefix("--") else { throw CLIParseError.invalidArguments }
                if inputPath == nil {
                    inputPath = argument
                } else if outputPath == nil {
                    outputPath = argument
                } else {
                    throw CLIParseError.invalidArguments
                }
                index += 1
            }
        }

        guard let inputPath, let outputPath else {
            throw CLIParseError.invalidArguments
        }

        let resizeMode = try resolveResizeMode(
            width: width,
            height: height,
            percentage: percentage,
            square: square
        )

        return CLIOptions(
            inputPath: inputPath,
            outputPath: outputPath,
            resizeMode: resizeMode,
            backend: backend,
            energy: energy,
            dimensionOrder: dimensionOrder,
            preScaleStrategy: preScaleStrategy,
            deterministic: deterministic,
            protectMaskPath: protectMaskPath,
            removeMaskPath: removeMaskPath,
            protectStrength: protectStrength,
            protectWeight: protectWeight,
            removalWeight: removalWeight,
            facePolicy: facePolicy,
            faceCadence: faceCadence,
            blurRadius: blurRadius,
            sobelThreshold: sobelThreshold,
            debug: debug,
            debugDirectory: debugDirectory,
            seamColor: seamColor,
            seamShape: seamShape,
            inputDirectory: inputDirectory,
            outputDirectory: outputDirectory,
            recursive: recursive,
            concurrency: concurrency
        )
    }

    private static func resolveResizeMode(
        width: Int?,
        height: Int?,
        percentage: Float?,
        square: Bool
    ) throws -> ResizeMode {
        let hasExact = width != nil || height != nil
        if square {
            guard !hasExact, percentage == nil else { throw CLIParseError.conflictingModes }
            return .square
        }
        if let percentage {
            guard !hasExact else { throw CLIParseError.conflictingModes }
            return .percentage(percentage)
        }
        guard let width, let height else {
            throw CLIParseError.invalidArguments
        }
        return .exact(width: width, height: height)
    }

    private static func parsePositiveFloat(_ string: String) -> Float? {
        guard let value = Float(string), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func parseNonNegativeFloat(_ string: String) -> Float? {
        guard let value = Float(string), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func parseBackend(_ string: String) throws -> BackendPreference {
        switch string {
        case "automatic": return .automatic
        case "cpu": return .cpu
        case "accelerate": return .accelerate
        case "metal": return .metal
        default: throw CLIParseError.invalidArguments
        }
    }

    private static func parseEnergy(_ string: String) throws -> EnergyMode {
        switch string {
        case "backward": return .backwardSobel
        case "forward": return .forwardLuma
        default: throw CLIParseError.invalidArguments
        }
    }

    private static func parseDimensionOrder(_ string: String) throws -> DimensionOrder {
        switch string {
        case "width-first": return .widthThenHeight
        case "height-first": return .heightThenWidth
        case "adaptive": return .adaptiveNormalizedCost
        default: throw CLIParseError.invalidArguments
        }
    }

    private static func parsePreScale(_ string: String) throws -> PreScaleStrategy {
        switch string {
        case "none": return .none
        case "lanczos-residual": return .lanczosThenExactResidual
        default: throw CLIParseError.invalidArguments
        }
    }

    private static func parseFacePolicy(_ string: String) throws -> FaceProtectionPolicy {
        switch string {
        case "caire": return .caireInspired(try CaireInspiredParameters())
        case "vision": return .visionQuality(try VisionQualityParameters())
        default: throw CLIParseError.invalidArguments
        }
    }
}
