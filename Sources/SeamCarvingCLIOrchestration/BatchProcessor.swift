import Foundation
import SeamCarvingCLIModel

public struct CLIBackendCapabilities: Sendable, Equatable {
    public let outputFormats: Set<CLIOutputFormat>
    public let supportsFaceProtection: Bool
    public let supportsDebugArtifacts: Bool

    public init(outputFormats: Set<CLIOutputFormat>, supportsFaceProtection: Bool, supportsDebugArtifacts: Bool) {
        self.outputFormats = outputFormats
        self.supportsFaceProtection = supportsFaceProtection
        self.supportsDebugArtifacts = supportsDebugArtifacts
    }
}

public protocol CLIImageBackend: Sendable {
    var capabilities: CLIBackendCapabilities { get }
    func process(_ options: CLIOptions) async throws -> CLIProcessResult
    func exitCode(for error: Error) -> CLIExitCode?
    func message(for error: Error) -> String?
}

public protocol CLIFileSystem: Sendable {
    func enumerateImages(at inputDirectory: String, recursive: Bool) throws -> CLIBatchInputEnumeration
    func outputPath(root: String, relativePath: String) -> String
    func createDirectory(_ path: String) throws
    func createParentDirectory(forOutputPath path: String) throws
}

public struct BatchFailure: Sendable, Equatable {
    public let relativePath: String
    public let message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

public struct BatchProcessSummary: Sendable, Equatable {
    public let successCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let failures: [BatchFailure]

    public init(successCount: Int, failedCount: Int, skippedCount: Int, failures: [BatchFailure]) {
        self.successCount = successCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.failures = failures
    }
}

public struct BatchProcessor: Sendable {
    public typealias ProcessFile = @Sendable (CLIOptions) async throws -> CLIProcessResult
    public typealias Logger = @Sendable (String) -> Void
    public typealias ErrorMessage = @Sendable (Error) -> String?

    private let logger: Logger
    private let processFile: ProcessFile
    private let errorMessage: ErrorMessage
    private let fileSystem: any CLIFileSystem

    public init(
        logger: @escaping Logger = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        },
        processFile: @escaping ProcessFile,
        errorMessage: @escaping ErrorMessage = { _ in nil }
    ) {
        self.init(logger: logger, processFile: processFile, errorMessage: errorMessage, fileSystem: FoundationCLIFileSystem())
    }

    public init(
        logger: @escaping Logger,
        processFile: @escaping ProcessFile,
        errorMessage: @escaping ErrorMessage,
        fileSystem: any CLIFileSystem
    ) {
        self.logger = logger
        self.processFile = processFile
        self.errorMessage = errorMessage
        self.fileSystem = fileSystem
    }

    public init(backend: any CLIImageBackend, logger: @escaping Logger = { message in
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }, fileSystem: any CLIFileSystem = FoundationCLIFileSystem()) {
        self.init(logger: logger, processFile: { try await backend.process($0) }, errorMessage: { backend.message(for: $0) }, fileSystem: fileSystem)
    }

    public func process(_ configuration: BatchConfiguration) async throws -> BatchProcessSummary {
        let enumeration = try enumerateJobs(configuration)
        var iterator = enumeration.jobs.makeIterator()
        var successCount = 0
        var failures: [BatchFailure] = []

        try await withThrowingTaskGroup(of: BatchJobResult.self) { group in
            for _ in 0..<min(configuration.concurrencyLimit, enumeration.jobs.count) {
                if let job = iterator.next() {
                    group.addTask { try await self.run(job: job, template: configuration.templateOptions) }
                }
            }

            while let result = try await group.next() {
                switch result {
                case .success(let relativePath, let processResult):
                    successCount += 1
                    logger("processed \(relativePath) -> \(processResult.width)x\(processResult.height) \(processResult.backend)")
                case .failure(let failure):
                    failures.append(failure)
                    logger("failed \(failure.relativePath): \(failure.message)")
                }

                if let nextJob = iterator.next() {
                    group.addTask { try await self.run(job: nextJob, template: configuration.templateOptions) }
                }
            }
        }

        let summary = BatchProcessSummary(
            successCount: successCount,
            failedCount: failures.count,
            skippedCount: enumeration.skippedCount,
            failures: failures.sorted { $0.relativePath < $1.relativePath }
        )
        logger(
            "batch complete: \(summary.successCount) succeeded, \(summary.failedCount) failed, \(summary.skippedCount) skipped"
        )
        return summary
    }

    private func enumerateJobs(_ configuration: BatchConfiguration) throws -> BatchEnumeration {
        try fileSystem.createDirectory(configuration.outputDirectory)
        let enumeration = try fileSystem.enumerateImages(at: configuration.inputDirectory, recursive: configuration.recursive)
        let jobs = enumeration.inputs.map { input in
            let relativeOutput = outputRelativePath(for: input.relativePath, explicitFormat: configuration.templateOptions.outputFormat)
            return BatchJob(inputPath: input.inputPath, outputPath: fileSystem.outputPath(root: configuration.outputDirectory, relativePath: relativeOutput), relativePath: input.relativePath)
        }

        return BatchEnumeration(jobs: jobs.sorted { normalizedSortKey($0.relativePath) < normalizedSortKey($1.relativePath) }, skippedCount: enumeration.skippedCount)
    }

    private func run(job: BatchJob, template: CLIOptions) async throws -> BatchJobResult {
        do {
            try fileSystem.createParentDirectory(forOutputPath: job.outputPath)
            let options = makePerFileOptions(inputPath: job.inputPath, outputPath: job.outputPath, template: template)
            let result = try await processFile(options)
            return .success(relativePath: job.relativePath, result: result)
        } catch is CancellationError {
            throw CancellationError()
        } catch let configurationError as CLIConfigurationError {
            return .failure(BatchFailure(relativePath: job.relativePath, message: configurationError.message))
        } catch {
            return .failure(BatchFailure(relativePath: job.relativePath, message: errorMessage(error) ?? "\(error)"))
        }
    }

    private func makePerFileOptions(inputPath: String, outputPath: String, template: CLIOptions) -> CLIOptions {
        CLIOptions(
            inputPath: inputPath,
            outputPath: outputPath,
            resizeMode: template.resizeMode,
            backend: template.backend,
            energy: template.energy,
            dimensionOrder: template.dimensionOrder,
            preScaleStrategy: template.preScaleStrategy,
            deterministic: template.deterministic,
            protectMaskPath: template.protectMaskPath,
            removeMaskPath: template.removeMaskPath,
            protectStrength: template.protectStrength,
            protectWeight: template.protectWeight,
            removalWeight: template.removalWeight,
            facePolicy: template.facePolicy,
            faceCadence: template.faceCadence,
            blurRadius: template.blurRadius,
            sobelThreshold: template.sobelThreshold,
            outputFormat: template.outputFormat,
            debug: false,
            debugDirectory: nil,
            seamColor: nil,
            seamShape: nil,
            inputDirectory: nil,
            outputDirectory: nil,
            recursive: false,
            concurrency: nil
        )
    }

    private func outputRelativePath(for inputRelativePath: String, explicitFormat: CLIOutputFormat?) -> String {
        guard let explicitFormat else { return inputRelativePath }

        let inputURL = URL(fileURLWithPath: inputRelativePath)
        let extensionName: String
        switch explicitFormat {
        case .png: extensionName = "png"
        case .jpeg: extensionName = "jpg"
        case .bmp: extensionName = "bmp"
        }
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + "." + extensionName
        let directory = inputURL.deletingLastPathComponent()
        if directory.path == "/" || directory.path == "." {
            return outputFileName
        }
        return directory.appendingPathComponent(outputFileName).path
    }

    private func normalizedSortKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping.lowercased()
    }
}

private struct BatchEnumeration {
    let jobs: [BatchJob]
    let skippedCount: Int
}

private struct BatchJob: Sendable, Equatable {
    let inputPath: String
    let outputPath: String
    let relativePath: String
}

private enum BatchJobResult: Sendable {
    case success(relativePath: String, result: CLIProcessResult)
    case failure(BatchFailure)
}

/// Foundation implementation used by the current Apple assembly. It is kept in
/// the portable orchestration target because Foundation supports Windows too;
/// future adapters can provide native semantics through `CLIFileSystem`.
public struct FoundationCLIFileSystem: CLIFileSystem {
    public init() {}

    public func enumerateImages(at inputDirectory: String, recursive: Bool) throws -> CLIBatchInputEnumeration {
        let root = URL(fileURLWithPath: inputDirectory, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIConfigurationError.incompatibleOptions("input directory does not exist: \(inputDirectory)")
        }
        let urls: [URL]
        if recursive {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            urls = (enumerator?.allObjects as? [URL]) ?? []
        } else {
            urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        }
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var skippedCount = 0
        let inputs: [CLIBatchInput] = try urls.compactMap { url in
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { return nil }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count)).replacingOccurrences(of: "\\", with: "/")
            guard ["png", "jpg", "jpeg", "bmp"].contains(URL(fileURLWithPath: relative).pathExtension.lowercased()) else { skippedCount += 1; return nil }
            return CLIBatchInput(inputPath: url.path, relativePath: relative)
        }
        return CLIBatchInputEnumeration(inputs: inputs, skippedCount: skippedCount)
    }

    public func outputPath(root: String, relativePath: String) -> String { URL(fileURLWithPath: root).appendingPathComponent(relativePath).path }
    public func createDirectory(_ path: String) throws { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
    public func createParentDirectory(forOutputPath path: String) throws { try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true) }
}
