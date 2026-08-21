#if os(macOS)
import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class CLIEndToEndTests: XCTestCase {
    func testResizeImageViaExecutable() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }

        // Generate a 32x24 PNG.
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-output-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            inputURL.path, outputURL.path,
            "--width", "20", "--height", "18",
            "--backend", "cpu", "--energy", "backward",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "stderr: \(String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")

        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("cannot reopen output")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    private static func writeGradientPNG(width: Int, height: Int, to url: URL) throws {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels += [v, v, v, 255]
            }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "CLIEndToEndTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
#else
import XCTest

final class CLIEndToEndTests: XCTestCase {
    func testMacOSOnly() throws {
        throw XCTSkip("seamcarve-cli process test is macOS-only")
    }
}
#endif
