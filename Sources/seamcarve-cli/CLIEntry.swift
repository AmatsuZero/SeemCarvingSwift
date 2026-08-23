#if os(macOS)
import Foundation
import SeamCarvingCLI

@main
enum CLIEntry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            print("Usage: seamcarve-cli INPUT OUTPUT --width PIXELS --height PIXELS [--backend automatic|cpu|accelerate|metal] [--energy backward|forward] [--order width-first|height-first|adaptive] [--pre-scale none|lanczos-residual] [--deterministic] [--protect-mask PATH --protect-strength hard|soft --protect-weight VALUE] [--remove-mask PATH --removal-weight VALUE] [--face-policy caire|vision --face-cadence once|each-pass]")
            exit(CLIExitCode.success.rawValue)
        }

        do {
            let options = try CLIOptions.parse(arguments)
            let result = try await CLIProcessor().process(options)
            print("\(result.width)x\(result.height) \(result.backend)")
            exit(CLIExitCode.success.rawValue)
        } catch {
            FileHandle.standardError.write(Data("error: \(message(for: error))\n".utf8))
            exit(CLIExitCode.exitCode(for: error).rawValue)
        }
    }

    private static func message(for error: Error) -> String {
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

#else
import Foundation

@main
enum UnsupportedCLIPlatform {
    static func main() async {
        FileHandle.standardError.write(
            Data("seamcarve-cli is available only on macOS\n".utf8)
        )
    }
}
#endif
