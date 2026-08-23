import Foundation
import SeamCarvingCore

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

    private let logger: Logger
    private let processFile: ProcessFile

    public init(
        logger: @escaping Logger = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        },
        processFile: @escaping ProcessFile
    ) {
        self.logger = logger
        self.processFile = processFile
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
        let inputRoot = URL(fileURLWithPath: configuration.inputDirectory, isDirectory: true).standardizedFileURL
        let outputRoot = URL(fileURLWithPath: configuration.outputDirectory, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIConfigurationError.incompatibleOptions("input directory does not exist: \(configuration.inputDirectory)")
        }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        var jobs: [BatchJob] = []
        var skippedCount = 0

        if configuration.recursive {
            let enumerator = FileManager.default.enumerator(
                at: inputRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }
                let relativePath = relativePath(for: url, base: inputRoot)
                if supportedImagePath(relativePath) {
                    jobs.append(makeJob(inputURL: url, relativePath: relativePath, outputRoot: outputRoot, template: configuration.templateOptions))
                } else {
                    skippedCount += 1
                }
            }
        } else {
            for url in try FileManager.default.contentsOfDirectory(at: inputRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }
                let relativePath = relativePath(for: url, base: inputRoot)
                if supportedImagePath(relativePath) {
                    jobs.append(makeJob(inputURL: url, relativePath: relativePath, outputRoot: outputRoot, template: configuration.templateOptions))
                } else {
                    skippedCount += 1
                }
            }
        }

        jobs.sort { normalizedSortKey($0.relativePath) < normalizedSortKey($1.relativePath) }
        return BatchEnumeration(jobs: jobs, skippedCount: skippedCount)
    }

    private func run(job: BatchJob, template: CLIOptions) async throws -> BatchJobResult {
        do {
            try FileManager.default.createDirectory(
                at: job.outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let options = makePerFileOptions(inputPath: job.inputURL.path, outputPath: job.outputURL.path, template: template)
            let result = try await processFile(options)
            return .success(relativePath: job.relativePath, result: result)
        } catch is CancellationError {
            throw CancellationError()
        } catch let imageIOError as CLIImageIOError {
            return .failure(BatchFailure(relativePath: job.relativePath, message: imageIOError.message))
        } catch let configurationError as CLIConfigurationError {
            return .failure(BatchFailure(relativePath: job.relativePath, message: configurationError.message))
        } catch {
            return .failure(BatchFailure(relativePath: job.relativePath, message: "\(error)"))
        }
    }

    private func makeJob(inputURL: URL, relativePath: String, outputRoot: URL, template: CLIOptions) -> BatchJob {
        let outputRelativePath = outputRelativePath(for: relativePath, explicitFormat: template.outputFormat)
        return BatchJob(
            inputURL: inputURL.standardizedFileURL,
            outputURL: outputRoot.appendingPathComponent(outputRelativePath, isDirectory: false),
            relativePath: relativePath
        )
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

    private func relativePath(for fileURL: URL, base baseURL: URL) -> String {
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        return String(fileURL.standardizedFileURL.path.dropFirst(basePath.count))
    }

    private func supportedImagePath(_ relativePath: String) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "bmp"
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
    let inputURL: URL
    let outputURL: URL
    let relativePath: String
}

private enum BatchJobResult: Sendable {
    case success(relativePath: String, result: CLIProcessResult)
    case failure(BatchFailure)
}
