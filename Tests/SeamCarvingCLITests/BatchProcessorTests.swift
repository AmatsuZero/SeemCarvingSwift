#if os(macOS)
import XCTest
import Foundation
@testable import SeamCarvingCLI

final class BatchProcessorTests: XCTestCase {
    func testSortsNormalizedPathsAndSkipsNonImages() async throws {
        let fixture = try TemporaryDirectory()
        let inputRoot = fixture.url.appendingPathComponent("input", isDirectory: true)
        let outputRoot = fixture.url.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputRoot, withIntermediateDirectories: true)

        try Data().write(to: inputRoot.appendingPathComponent("z.JPG"))
        try Data().write(to: inputRoot.appendingPathComponent("a.png"))
        try Data().write(to: inputRoot.appendingPathComponent("b.bmp"))
        try Data("ignore".utf8).write(to: inputRoot.appendingPathComponent("notes.txt"))

        let batch = try parseBatchConfiguration([
            "--input-dir", inputRoot.path,
            "--output-dir", outputRoot.path,
            "--width", "8", "--height", "6",
            "--backend", "cpu",
            "--concurrency", "1",
        ])
        let recorder = InvocationRecorder()

        let summary = try await BatchProcessor(
            logger: { _ in },
            processFile: { options in
                await recorder.recordStart(
                    input: Self.relativePath(for: options.inputPath, base: inputRoot),
                    output: Self.relativePath(for: options.outputPath, base: outputRoot)
                )
                try Data("ok".utf8).write(to: URL(fileURLWithPath: options.outputPath))
                await recorder.recordFinish()
                return CLIProcessResult(width: 8, height: 6, backend: .cpu)
            }
        ).process(batch)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.inputs, ["a.png", "b.bmp", "z.JPG"])
        XCTAssertEqual(snapshot.outputs, ["a.png", "b.bmp", "z.JPG"])
        XCTAssertEqual(summary.successCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
    }

    func testRecursiveModePreservesNestedRelativePaths() async throws {
        let fixture = try TemporaryDirectory()
        let inputRoot = fixture.url.appendingPathComponent("input", isDirectory: true)
        let nested = inputRoot.appendingPathComponent("deep/inside", isDirectory: true)
        let outputRoot = fixture.url.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        try Data().write(to: inputRoot.appendingPathComponent("root.png"))
        try Data().write(to: nested.appendingPathComponent("nested.jpeg"))

        let batch = try parseBatchConfiguration([
            "--input-dir", inputRoot.path,
            "--output-dir", outputRoot.path,
            "--width", "8", "--height", "6",
            "--backend", "cpu",
            "--recursive",
            "--concurrency", "1",
        ])
        let recorder = InvocationRecorder()

        let summary = try await BatchProcessor(
            logger: { _ in },
            processFile: { options in
                let outputURL = URL(fileURLWithPath: options.outputPath)
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.deletingLastPathComponent().path))
                await recorder.recordStart(
                    input: Self.relativePath(for: options.inputPath, base: inputRoot),
                    output: Self.relativePath(for: options.outputPath, base: outputRoot)
                )
                try Data("ok".utf8).write(to: outputURL)
                await recorder.recordFinish()
                return CLIProcessResult(width: 8, height: 6, backend: .cpu)
            }
        ).process(batch)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.inputs, ["deep/inside/nested.jpeg", "root.png"])
        XCTAssertEqual(snapshot.outputs, ["deep/inside/nested.jpeg", "root.png"])
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testRespectsConcurrencyUpperBound() async throws {
        let fixture = try TemporaryDirectory()
        let inputRoot = fixture.url.appendingPathComponent("input", isDirectory: true)
        let outputRoot = fixture.url.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputRoot, withIntermediateDirectories: true)

        for index in 0..<6 {
            try Data().write(to: inputRoot.appendingPathComponent("image-\(index).png"))
        }

        let batch = try parseBatchConfiguration([
            "--input-dir", inputRoot.path,
            "--output-dir", outputRoot.path,
            "--width", "8", "--height", "6",
            "--backend", "cpu",
            "--concurrency", "2",
        ])
        let recorder = InvocationRecorder()

        let summary = try await BatchProcessor(
            logger: { _ in },
            processFile: { options in
                await recorder.recordStart(
                    input: Self.relativePath(for: options.inputPath, base: inputRoot),
                    output: Self.relativePath(for: options.outputPath, base: outputRoot)
                )
                try await Task.sleep(for: .milliseconds(50))
                try Data("ok".utf8).write(to: URL(fileURLWithPath: options.outputPath))
                await recorder.recordFinish()
                return CLIProcessResult(width: 8, height: 6, backend: .cpu)
            }
        ).process(batch)

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(summary.successCount, 6)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertLessThanOrEqual(snapshot.maxInFlight, 2)
    }

    func testContinuesAfterPartialFailuresAndLogsRelativePaths() async throws {
        let fixture = try TemporaryDirectory()
        let inputRoot = fixture.url.appendingPathComponent("input", isDirectory: true)
        let outputRoot = fixture.url.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputRoot, withIntermediateDirectories: true)

        try Data().write(to: inputRoot.appendingPathComponent("good.png"))
        try Data().write(to: inputRoot.appendingPathComponent("bad.bmp"))
        try Data("ignore".utf8).write(to: inputRoot.appendingPathComponent("notes.md"))

        let batch = try parseBatchConfiguration([
            "--input-dir", inputRoot.path,
            "--output-dir", outputRoot.path,
            "--width", "8", "--height", "6",
            "--backend", "cpu",
            "--concurrency", "1",
        ])
        let logs = LogRecorder()

        let summary = try await BatchProcessor(
            logger: { message in
                logs.record(message)
            },
            processFile: { options in
                if options.inputPath.hasSuffix("/bad.bmp") || options.inputPath.hasSuffix("bad.bmp") {
                    struct ExpectedFailure: Error, CustomStringConvertible {
                        var description: String { "expected batch failure" }
                    }
                    throw ExpectedFailure()
                }
                try Data("ok".utf8).write(to: URL(fileURLWithPath: options.outputPath))
                return CLIProcessResult(width: 8, height: 6, backend: .cpu)
            }
        ).process(batch)

        let messages = logs.messages
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.failures.map(\.relativePath), ["bad.bmp"])
        XCTAssertTrue(messages.contains(where: { $0.contains("bad.bmp") }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("good.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("bad.bmp").path))
    }

    func testBatchConfigurationRejectsSingleStreamAndDebugConflicts() throws {
        XCTAssertThrowsError(try CLIConfiguration.parse(arguments: [
            "-", "out.png",
            "--input-dir", "src",
            "--output-dir", "dst",
            "--width", "8", "--height", "6",
        ]))

        XCTAssertThrowsError(try CLIConfiguration.parse(arguments: [
            "--input-dir", "src",
            "--output-dir", "dst",
            "--width", "8", "--height", "6",
            "--debug",
        ]))
    }

    private func parseBatchConfiguration(_ arguments: [String]) throws -> BatchConfiguration {
        let configuration = try CLIConfiguration.parse(arguments: arguments)
        guard case .batch(let batch) = configuration else {
            XCTFail("expected batch configuration")
            throw TestFailure()
        }
        return batch
    }

    private static func relativePath(for path: String, base: URL) -> String {
        let standardizedBase = base.standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = standardizedBase.hasSuffix("/") ? standardizedBase : standardizedBase + "/"
        return String(standardizedPath.dropFirst(prefix.count))
    }
}

private actor InvocationRecorder {
    private(set) var inputs: [String] = []
    private(set) var outputs: [String] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0

    func recordStart(input: String, output: String) {
        inputs.append(input)
        outputs.append(output)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
    }

    func recordFinish() {
        inFlight -= 1
    }

    func snapshot() -> (inputs: [String], outputs: [String], maxInFlight: Int) {
        (inputs, outputs, maxInFlight)
    }
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("seam-batch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct TestFailure: Error {}
#else
import XCTest

final class BatchProcessorTests: XCTestCase {
    func testMacOSOnly() throws {
        throw XCTSkip("batch processor tests are macOS-only")
    }
}
#endif
