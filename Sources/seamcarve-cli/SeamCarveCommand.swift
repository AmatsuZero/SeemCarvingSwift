#if os(macOS)
import ArgumentParser
import Foundation
import SeamCarvingCLI

@main
struct SeamCarveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seamcarve-cli",
        abstract: "Content-aware image resizing using seam carving.",
        discussion: """
        INPUT may be a local path, an http(s) URL, or '-' to read binary image data from stdin.
        OUTPUT may be a local path or '-' to write only image bytes to stdout.
        Batch mode uses --input-dir and --output-dir instead of positional INPUT/OUTPUT.
        """
    )

    @OptionGroup
    var arguments: CLIParsedArguments

    mutating func run() async throws {
        do {
            switch try CLIConfiguration.parse(parsedArguments: arguments) {
            case .single(let options):
                let result = try await CLIProcessor().process(options)
                // Binary stdout mode (`-` output) writes only image bytes; the summary
                // is suppressed so it cannot pollute stdout.
                if options.outputPath != "-" {
                    print("\(result.width)x\(result.height) \(result.backend)")
                }
            case .batch(let batch):
                let summary = try await BatchProcessor(processFile: { options in
                    try await CLIProcessor().process(options)
                }).process(batch)
                if summary.failedCount != 0 {
                    throw ExitCode(CLIExitCode.dataError.rawValue)
                }
            }
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            FileHandle.standardError.write(Data("error: \(message(for: error))\n".utf8))
            throw ExitCode(CLIExitCode.exitCode(for: error).rawValue)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case let imageIOError as CLIImageIOError:
            return imageIOError.message
        case let configurationError as CLIConfigurationError:
            return configurationError.message
        case let parseError as CLIParseError:
            return parseError.message
        case is CancellationError:
            return "cancelled"
        default:
            return "\(error)"
        }
    }
}
#endif
