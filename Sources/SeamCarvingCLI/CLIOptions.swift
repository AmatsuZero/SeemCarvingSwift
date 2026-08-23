import Foundation
import SeamCarvingCore
import SeamCarvingVision

public enum CLIParseError: Error, Equatable {
    case invalidArguments
}

public struct CLIOptions: Sendable, Equatable {
    public let inputPath: String
    public let outputPath: String
    public let width: Int
    public let height: Int
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

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var inputPath: String?
        var outputPath: String?
        var width: Int?
        var height: Int?
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
                guard index + 1 < arguments.count, let value = Float(arguments[index + 1]), value.isFinite, value >= 0 else {
                    throw CLIParseError.invalidArguments
                }
                protectWeight = value
                if case .soft = protectStrength { protectStrength = .soft(value) }
                index += 2
            case "--removal-weight":
                guard index + 1 < arguments.count, let value = Float(arguments[index + 1]), value.isFinite, value >= 0 else {
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

        guard let inputPath, let outputPath, let width, let height else {
            throw CLIParseError.invalidArguments
        }

        return CLIOptions(
            inputPath: inputPath,
            outputPath: outputPath,
            width: width,
            height: height,
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
            faceCadence: faceCadence
        )
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
