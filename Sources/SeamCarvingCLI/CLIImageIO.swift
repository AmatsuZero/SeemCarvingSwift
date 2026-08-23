import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SeamCarvingCore
import SeamCarvingApple

/// Identifies which kind of user mask failed dimension validation.
public enum CLIMaskKind: Sendable, Equatable {
    case protection
    case removal

    var label: String {
        switch self {
        case .protection: return "protection"
        case .removal: return "removal"
        }
    }
}

/// Input/output errors surfaced by the CLI pipeline.
///
/// These map to `CLIExitCode.dataError` (65) so decode failures, unsupported
/// formats, mask dimension mismatches and encode failures share one stable code.
public enum CLIImageIOError: Error, Equatable {
    case cannotDecodeInput
    case cannotDecodeMask(String)
    case maskDimensionsMismatch(kind: CLIMaskKind, expected: PixelSize, actual: PixelSize)
    case unsupportedOutputFormat(String)
    case cannotEncodeOutput

    public var message: String {
        switch self {
        case .cannotDecodeInput:
            return "cannot decode input"
        case .cannotDecodeMask(let path):
            return "cannot decode mask at \(path)"
        case .maskDimensionsMismatch(let kind, let expected, let actual):
            return "\(kind.label) mask dimensions \(actual.width)x\(actual.height) do not match input \(expected.width)x\(expected.height)"
        case .unsupportedOutputFormat(let ext):
            return "unsupported output format \(ext)"
        case .cannotEncodeOutput:
            return "cannot encode output"
        }
    }
}

/// Image decoding, mask loading and output encoding for the CLI.
public enum CLIImageIO {
    /// Decodes the image at `path` into a `CGImage`.
    public static func readImage(fromPath path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIImageIOError.cannotDecodeInput
        }
        return image
    }

    /// Loads a mask image as a grayscale `Mask` using per-pixel max channel.
    public static func loadMask(path: String) throws -> Mask {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIImageIOError.cannotDecodeMask(path)
        }
        let rgba = try CGImageBridge.decode(image)
        var values = [Float](repeating: 0, count: rgba.width * rgba.height)
        for index in values.indices {
            let base = index * 4
            let intensity = max(rgba.pixels[base], max(rgba.pixels[base + 1], rgba.pixels[base + 2]))
            values[index] = Float(intensity) / 255
        }
        return try Mask(width: rgba.width, height: rgba.height, values: values)
    }

    /// Encodes `image` to `path`, choosing the format from the path extension.
    public static func writeImage(_ image: CGImage, toPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard let type = outputUTType(forExtension: url.pathExtension) else {
            throw CLIImageIOError.unsupportedOutputFormat(url.pathExtension)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CLIImageIOError.unsupportedOutputFormat(url.pathExtension)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CLIImageIOError.cannotEncodeOutput
        }
    }

    /// Maps a lowercased extension to its output `UTType`, or `nil` if unsupported.
    public static func outputUTType(forExtension ext: String) -> UTType? {
        switch ext.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }
}
