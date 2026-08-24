import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SeamCarvingCore
import SeamCarvingAppleImaging

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

/// Output image format selectable via `--format` or the output path extension.
public enum CLIOutputFormat: String, Sendable, Equatable {
    case png
    case jpeg
    case bmp

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .bmp: return .bmp
        }
    }

    /// Parses a user-facing format name (`png`, `jpg`/`jpeg`, `bmp`).
    static func parse(_ string: String) -> CLIOutputFormat? {
        switch string.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "bmp": return .bmp
        default: return nil
        }
    }
}

/// Input/output errors surfaced by the CLI pipeline.
///
/// These map to `CLIExitCode.dataError` (65) so decode failures, unsupported
/// formats, mask dimension mismatches, encode failures and network errors share
/// one stable code.
public enum CLIImageIOError: Error, Equatable {
    case cannotDecodeInput
    case cannotDecodeMask(String)
    case maskDimensionsMismatch(kind: CLIMaskKind, expected: PixelSize, actual: PixelSize)
    case unsupportedOutputFormat(String)
    case cannotEncodeOutput
    case cannotWriteOutput(String)
    case networkFailure(String)

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
        case .cannotWriteOutput(let path):
            return "cannot write output to \(path)"
        case .networkFailure(let detail):
            return "network failure: \(detail)"
        }
    }
}

/// Image decoding, mask loading and output encoding for the CLI.
///
/// Input and output honor a `-` convention: `-` as input reads the complete
/// binary payload from standard input, and `-` as output writes only the encoded
/// image bytes to standard output (no summary, progress, or diagnostics). All
/// diagnostics go to stderr. Remote inputs are accepted only for explicit
/// `http`/`https` URLs; any other string is treated as a local path.
public enum CLIImageIO {
    /// Decodes the image at `path`, a remote URL, or standard input (`-`).
    public static func readImage(fromPath path: String) async throws -> CGImage {
        try await readImage(fromPath: path) { url in
            try await download(from: url)
        }
    }

    /// Decodes an image using an injected remote downloader. The injection
    /// point keeps URL input deterministic and testable without requiring a
    /// live network connection.
    public static func readImage(
        fromPath path: String,
        downloader: @escaping @Sendable (URL) async throws -> Data
    ) async throws -> CGImage {
        if path == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return try decodeImage(from: data)
        }
        if let url = remoteURL(from: path) {
            let data: Data
            do {
                data = try await downloader(url)
            } catch let error as CLIImageIOError {
                throw error
            } catch {
                throw CLIImageIOError.networkFailure("\(url.absoluteString): \(error.localizedDescription)")
            }
            return try decodeImage(from: data)
        }
        return try readLocalImage(fromPath: path)
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

    /// Encodes `image` with `format` and writes it to `path` or standard output (`-`).
    public static func writeImage(_ image: CGImage, toPath path: String, format: CLIOutputFormat) throws {
        let data = try encodeImage(image, format: format)
        if path == "-" {
            FileHandle.standardOutput.write(data)
        } else {
            do {
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                throw CLIImageIOError.cannotWriteOutput(path)
            }
        }
    }

    // MARK: - Input helpers

    private static func remoteURL(from path: String) -> URL? {
        guard let url = URL(string: path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func download(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else {
                    throw CLIImageIOError.networkFailure("\(url.absoluteString) returned HTTP \(http.statusCode)")
                }
            }
            return data
        } catch let error as CLIImageIOError {
            throw error
        } catch {
            throw CLIImageIOError.networkFailure("\(url.absoluteString): \(error.localizedDescription)")
        }
    }

    private static func decodeImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIImageIOError.cannotDecodeInput
        }
        return image
    }

    private static func readLocalImage(fromPath path: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIImageIOError.cannotDecodeInput
        }
        return image
    }

    // MARK: - Output helpers

    private static func encodeImage(_ image: CGImage, format: CLIOutputFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw CLIImageIOError.cannotEncodeOutput
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CLIImageIOError.cannotEncodeOutput
        }
        return data as Data
    }
}
