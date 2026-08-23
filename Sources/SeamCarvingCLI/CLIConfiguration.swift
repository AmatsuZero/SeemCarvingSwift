import Foundation
import SeamCarvingCore

/// How the target image size is specified on the command line.
///
/// `exact` is fully implemented. `percentage` and `square` are parsed and
/// validated here so the CLI surface (the parity contract) is frozen up front,
/// but their resize semantics are implemented in a later task; until then the
/// processor rejects them with a usage error rather than silently ignoring them.
public enum ResizeMode: Sendable, Equatable {
    case exact(width: Int, height: Int)
    case percentage(Float)
    case square
}

/// RGBA seam-overlay color used by debug/seam visualization (reserved for a
/// later task). Parsed from `RRGGBB`, `RRGGBBAA`, `#RRGGBB`, or `#RRGGBBAA`.
public struct SeamColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Returns `nil` for malformed input such as wrong length or non-hex digits.
    public init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        red = bytes[0]
        green = bytes[1]
        blue = bytes[2]
        alpha = bytes.count == 4 ? bytes[3] : 255
    }
}

/// Seam visualization shape (reserved for a later task).
public enum SeamShape: String, Sendable, Equatable {
    case line
    case points
}

/// Stable exit codes for `seamcarve-cli`, following BSD `sysexits` conventions.
///
/// stdout/stderr contract:
/// - Normal (non-binary) mode writes the result summary (`WxH backend`) to
///   stdout and all diagnostics (errors and progress) to stderr.
/// - Exit code `0` means success. Any other code means failure and is preceded
///   by an `error: ...` line on stderr.
/// - Cancellation (`SIGINT`) maps to 130 (`128 + SIGINT`).
public enum CLIExitCode: Int32, Sendable, Equatable {
    case success = 0
    /// Invalid arguments or unsupported configuration (`EX_USAGE`).
    case usage = 64
    /// Input/output errors: undecodable input, mask dimension mismatch,
    /// unsupported output format, encode failure (`EX_DATAERR`).
    case dataError = 65
    /// Internal processing error (`EX_SOFTWARE`).
    case softwareError = 70
    /// Cancellation (`128 + SIGINT`).
    case cancelled = 130

    /// Maps a thrown error to its stable exit code.
    public static func exitCode(for error: Error) -> CLIExitCode {
        if error is CancellationError { return .cancelled }
        if error is CLIParseError { return .usage }
        if error is CLIConfigurationError { return .usage }
        if error is CLIImageIOError { return .dataError }
        return .softwareError
    }
}

/// Configuration errors raised after parsing, when each parsed option is valid
/// individually but cannot be executed (for example a reserved option or an
/// incompatible option combination).
public enum CLIConfigurationError: Error, Equatable {
    case reservedOptionNotImplemented(String)
    case incompatibleOptions(String)
    case missingRequiredOption(String)

    public var message: String {
        switch self {
        case .reservedOptionNotImplemented(let option):
            return "option \(option) is reserved and not yet implemented"
        case .incompatibleOptions(let detail):
            return detail
        case .missingRequiredOption(let detail):
            return detail
        }
    }
}

/// Top-level CLI execution mode selected from the raw argument vector.
public enum CLIConfiguration: Sendable, Equatable {
    case single(CLIOptions)
    case batch(BatchConfiguration)

    public static func parse(arguments: [String]) throws -> CLIConfiguration {
        let scan = try BatchArgumentScan(arguments: arguments)
        guard scan.isBatchMode else {
            return .single(try CLIOptions.parse(arguments))
        }

        guard let inputDirectory = scan.inputDirectory,
              let outputDirectory = scan.outputDirectory else {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode requires both --input-dir and --output-dir"
            )
        }
        guard scan.positionalArguments.isEmpty else {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode does not accept positional INPUT/OUTPUT or stdin/stdout paths"
            )
        }

        let template = try CLIOptions.parse(["__batch_input__", "__batch_output__"] + arguments)
        try validateBatchTemplate(template, inputDirectory: inputDirectory, outputDirectory: outputDirectory)

        return .batch(
            BatchConfiguration(
                templateOptions: template,
                inputDirectory: inputDirectory,
                outputDirectory: outputDirectory,
                recursive: template.recursive,
                concurrencyLimit: template.concurrency ?? BatchConfiguration.defaultConcurrency
            )
        )
    }

    private static func validateBatchTemplate(
        _ template: CLIOptions,
        inputDirectory: String,
        outputDirectory: String
    ) throws {
        if inputDirectory == "-" || outputDirectory == "-" {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode requires local input/output directories, not stdin/stdout"
            )
        }
        if looksLikeRemoteURL(inputDirectory) || looksLikeRemoteURL(outputDirectory) {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode requires local input/output directories, not remote URLs"
            )
        }
        if template.debug || template.debugDirectory != nil || template.seamColor != nil || template.seamShape != nil {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode does not support debug artifacts; use single-image mode instead"
            )
        }
        if template.protectMaskPath != nil || template.removeMaskPath != nil {
            throw CLIConfigurationError.incompatibleOptions(
                "batch mode does not support single-file mask arguments"
            )
        }
    }

    private static func looksLikeRemoteURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

public struct BatchConfiguration: Sendable, Equatable {
    public static let defaultConcurrency = 2

    public let templateOptions: CLIOptions
    public let inputDirectory: String
    public let outputDirectory: String
    public let recursive: Bool
    public let concurrencyLimit: Int

    public init(
        templateOptions: CLIOptions,
        inputDirectory: String,
        outputDirectory: String,
        recursive: Bool,
        concurrencyLimit: Int
    ) {
        self.templateOptions = templateOptions
        self.inputDirectory = inputDirectory
        self.outputDirectory = outputDirectory
        self.recursive = recursive
        self.concurrencyLimit = concurrencyLimit
    }
}

private struct BatchArgumentScan {
    let inputDirectory: String?
    let outputDirectory: String?
    let positionalArguments: [String]

    var isBatchMode: Bool {
        inputDirectory != nil || outputDirectory != nil
    }

    init(arguments: [String]) throws {
        var inputDirectory: String?
        var outputDirectory: String?
        var positionalArguments: [String] = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--input-dir":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                inputDirectory = arguments[index + 1]
                index += 2
            case "--output-dir":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                outputDirectory = arguments[index + 1]
                index += 2
            case "--width", "--height", "--percentage", "--backend", "--energy", "--order", "--pre-scale",
                 "--protect-mask", "--remove-mask", "--protect-strength", "--protect-weight", "--removal-weight",
                 "--face-policy", "--face-cadence", "--blur-radius", "--sobel-threshold", "--format",
                 "--debug-directory", "--seam-color", "--seam-shape", "--concurrency":
                guard index + 1 < arguments.count else { throw CLIParseError.invalidArguments }
                index += 2
            case "--square", "--deterministic", "--debug", "--recursive":
                index += 1
            default:
                if !argument.hasPrefix("--") {
                    positionalArguments.append(argument)
                    index += 1
                } else {
                    index += 1
                }
            }
        }

        self.inputDirectory = inputDirectory
        self.outputDirectory = outputDirectory
        self.positionalArguments = positionalArguments
    }
}
