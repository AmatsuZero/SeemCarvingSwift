import Foundation
import SeamCarvingCore

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

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var inputPath: String?
        var outputPath: String?
        var width: Int?
        var height: Int?
        var backend = BackendPreference.automatic
        var energy = EnergyMode.backwardSobel

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
            energy: energy
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
}
