#if os(macOS)
import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SeamCarvingCLI

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

    func testResizeImageWithProtectMask() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }

        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-mask-input-\(UUID().uuidString).png")
        let maskURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-mask-protect-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-mask-output-\(UUID().uuidString).png")
        defer {
            for url in [inputURL, maskURL, outputURL] { try? FileManager.default.removeItem(at: url) }
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)
        try Self.writeMaskPNG(width: 32, height: 24, protectedRect: CGRect(x: 12, y: 8, width: 8, height: 8), to: maskURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            inputURL.path, outputURL.path,
            "--width", "20", "--height", "18",
            "--backend", "cpu", "--protect-mask", maskURL.path,
            "--protect-strength", "hard",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "stderr: \(String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")
        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("cannot reopen masked output")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    func testProcessorResizesImageDirectly() async throws {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-output-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)

        let options = try CLIOptions.parse([
            inputURL.path, outputURL.path,
            "--width", "20", "--height", "18",
            "--backend", "cpu", "--energy", "backward",
        ])
        let result = try await CLIProcessor().process(options)

        XCTAssertEqual(result.width, 20)
        XCTAssertEqual(result.height, 18)
        XCTAssertEqual(result.backend, .cpu)

        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("cannot reopen processor output")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    func testProcessorPercentageResize() async throws {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-pct-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-pct-output-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)

        let options = try CLIOptions.parse([
            inputURL.path, outputURL.path,
            "--percentage", "50", "--backend", "cpu",
        ])
        let result = try await CLIProcessor().process(options)

        XCTAssertEqual(result.width, 16)
        XCTAssertEqual(result.height, 12)
        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("cannot reopen percentage output")
            return
        }
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 12)
    }

    func testProcessorSquareResize() async throws {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-sq-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-sq-output-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)

        let options = try CLIOptions.parse([
            inputURL.path, outputURL.path,
            "--square", "--backend", "cpu",
        ])
        let result = try await CLIProcessor().process(options)

        XCTAssertEqual(result.width, 24)
        XCTAssertEqual(result.height, 24)
    }

    func testProcessorRejectsReservedOptions() async throws {
        let reservedCases: [[String]] = [
            ["--debug"],
            ["--debug-directory", "seams"],
            ["--seam-color", "#ff0000"],
            ["--seam-shape", "line"],
            ["--input-dir", "src"],
            ["--output-dir", "dst"],
            ["--recursive"],
            ["--concurrency", "4"],
        ]
        for extra in reservedCases {
            var args = ["in.png", "out.png", "--width", "20", "--height", "18"]
            args.append(contentsOf: extra)
            let options = try CLIOptions.parse(args)
            do {
                _ = try await CLIProcessor().process(options)
                XCTFail("expected reserved option rejection for \(extra.joined(separator: " "))")
            } catch let error as CLIConfigurationError {
                XCTAssertEqual(CLIExitCode.exitCode(for: error), .usage)
            }
        }
    }

    func testProcessorRejectsForwardEnergyWithControls() async throws {
        let cases: [[String]] = [
            ["--energy", "forward", "--blur-radius", "2"],
            ["--energy", "forward", "--sobel-threshold", "0.5"],
        ]
        for extra in cases {
            var args = ["in.png", "out.png", "--width", "20", "--height", "18"]
            args.append(contentsOf: extra)
            let options = try CLIOptions.parse(args)
            do {
                _ = try await CLIProcessor().process(options)
                XCTFail("expected incompatible options error for \(extra.joined(separator: " "))")
            } catch let error as CLIConfigurationError {
                XCTAssertEqual(CLIExitCode.exitCode(for: error), .usage)
            }
        }
    }

    func testProcessorRejectsMaskDimensionMismatch() async throws {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-mismatch-input-\(UUID().uuidString).png")
        let maskURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-mismatch-mask-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-proc-mismatch-output-\(UUID().uuidString).png")
        defer {
            for url in [inputURL, maskURL, outputURL] { try? FileManager.default.removeItem(at: url) }
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)
        try Self.writeMaskPNG(width: 16, height: 12, protectedRect: CGRect(x: 4, y: 4, width: 8, height: 4), to: maskURL)

        let options = try CLIOptions.parse([
            inputURL.path, outputURL.path,
            "--width", "20", "--height", "18",
            "--protect-mask", maskURL.path, "--protect-strength", "hard",
        ])
        do {
            _ = try await CLIProcessor().process(options)
            XCTFail("expected mask dimension mismatch")
        } catch let error as CLIImageIOError {
            XCTAssertEqual(CLIExitCode.exitCode(for: error), .dataError)
        }
    }

    func testBMPOutputViaExtension() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-bmp-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-bmp-output-\(UUID().uuidString).bmp")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            inputURL.path, outputURL.path,
            "--width", "20", "--height", "18", "--backend", "cpu",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "stderr: \(String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")

        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("cannot reopen BMP output")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    func testBMPOutputViaFormatFlagToStdout() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-bmpfmt-input-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)
        let inputData = try Data(contentsOf: inputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-", "-", "--width", "20", "--height", "18", "--backend", "cpu", "--format", "bmp"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(inputData)
        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "stderr: \(String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(Array(stdoutData.prefix(2)), [0x42, 0x4D])
        guard let source = CGImageSourceCreateWithData(stdoutData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("stdout is not a decodable BMP")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    func testStdinStdoutBinaryRoundTrip() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-stream-input-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try Self.writeGradientPNG(width: 32, height: 24, to: inputURL)
        let inputData = try Data(contentsOf: inputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-", "-", "--width", "20", "--height", "18", "--backend", "cpu"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        stdinPipe.fileHandleForWriting.write(inputData)
        try stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(Array(stdoutData.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertFalse(String(data: stdoutData, encoding: .utf8)?.contains("20x18") ?? false)
        guard let source = CGImageSourceCreateWithData(stdoutData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            XCTFail("stdout is not a decodable PNG")
            return
        }
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 18)
    }

    func testMissingInputExitsDataError() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["/nonexistent/input.png", "/tmp/out.png", "--width", "20", "--height", "18"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 65)
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(stderr.contains("cannot decode input"))
    }

    func testInvalidArgumentsExitUsage() throws {
        guard let cliPath = ProcessInfo.processInfo.environment["SEAMCARVE_CLI_PATH"] else {
            throw XCTSkip("SEAMCARVE_CLI_PATH not set")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["in.png", "out.png", "--width", "abc", "--height", "18"]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 64)
    }

    func testRemoteURLInputWithInjectedDownloader() async throws {
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("cli-url-input-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try Self.writeGradientPNG(width: 8, height: 6, to: inputURL)
        let inputData = try Data(contentsOf: inputURL)

        let image = try await CLIImageIO.readImage(fromPath: "https://example.invalid/image.png") { url in
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "example.invalid")
            return inputData
        }
        XCTAssertEqual(image.width, 8)
        XCTAssertEqual(image.height, 6)
    }

    func testRemoteURLFailureMapsToNetworkError() async throws {
        do {
            _ = try await CLIImageIO.readImage(fromPath: "https://example.invalid/image.png") { _ in
                throw URLError(.cannotConnectToHost)
            }
            XCTFail("expected network failure")
        } catch let error as CLIImageIOError {
            guard case .networkFailure = error else {
                return XCTFail("unexpected image I/O error: \(error)")
            }
            XCTAssertEqual(CLIExitCode.exitCode(for: error), .dataError)
        }
    }

    func testOutputWriteFailureMapsToDataError() throws {
        let image = try Self.makeGradientImage(width: 4, height: 4)
        do {
            try CLIImageIO.writeImage(image, toPath: "/nonexistent-directory/output.png", format: .png)
            XCTFail("expected output write failure")
        } catch let error as CLIImageIOError {
            XCTAssertEqual(CLIExitCode.exitCode(for: error), .dataError)
            guard case .cannotWriteOutput = error else {
                return XCTFail("unexpected image I/O error: \(error)")
            }
        }
    }

    private static func writeGradientPNG(width: Int, height: Int, to url: URL) throws {
        let image = try makeGradientImage(width: width, height: height)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "CLIEndToEndTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func makeGradientImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels += [v, v, v, 255]
            }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    private static func writeMaskPNG(width: Int, height: Int, protectedRect: CGRect, to url: URL) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height where protectedRect.contains(CGPoint(x: width / 2, y: y)) {
            for x in 0..<width where protectedRect.contains(CGPoint(x: x, y: y)) {
                let base = (y * width + x) * 4
                pixels[base] = 255
                pixels[base + 1] = 255
                pixels[base + 2] = 255
                pixels[base + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "CLIEndToEndTests", code: 2) }
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
