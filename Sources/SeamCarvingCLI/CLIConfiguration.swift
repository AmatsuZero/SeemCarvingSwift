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
/// individually but cannot be executed yet (for example a reserved resize mode).
public enum CLIConfigurationError: Error, Equatable {
    case reservedResizeModeNotImplemented(ResizeMode)

    public var message: String {
        switch self {
        case .reservedResizeModeNotImplemented(let mode):
            switch mode {
            case .exact(let width, let height):
                return "exact resize (\(width)x\(height)) is not applicable"
            case .percentage(let value):
                return "percentage resize is reserved and not yet implemented (\(value))"
            case .square:
                return "square resize is reserved and not yet implemented"
            }
        }
    }
}
