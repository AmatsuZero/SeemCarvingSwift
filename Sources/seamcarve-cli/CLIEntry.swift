#if os(macOS)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SeamCarvingCore
import SeamCarvingCLI
import SeamCarvingApple

@main
enum CLIEntry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            print("Usage: seamcarve-cli INPUT OUTPUT --width PIXELS --height PIXELS [--backend automatic|cpu|accelerate|metal] [--energy backward|forward]")
            exit(0)
        }

        let options: CLIOptions
        do {
            options = try CLIOptions.parse(arguments)
        } catch {
            FileHandle.standardError.write(Data("error: invalid arguments\n".utf8))
            exit(64)
        }

        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: options.inputPath) as CFURL, nil),
              let inputImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            FileHandle.standardError.write(Data("error: cannot decode input\n".utf8))
            exit(65)
        }

        let carver: AppleSeamCarver
        do {
            carver = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: options.backend))
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(70)
        }

        var resizeOptions = ResizeOptions(energyMode: options.energy)
        resizeOptions.progress = { (progress: ResizeProgress) in
            FileHandle.standardError.write(Data("progress \(progress.completedEdits)/\(progress.totalEdits)\n".utf8))
        }

        let result: CGImage
        do {
            result = try await carver.resize(
                inputImage,
                toPixelSize: try PixelSize(width: options.width, height: options.height),
                options: resizeOptions
            )
        } catch is CancellationError {
            exit(130)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(70)
        }

        let outputURL = URL(fileURLWithPath: options.outputPath)
        guard let type = outputUTType(for: outputURL.pathExtension),
              let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("error: unsupported output format\n".utf8))
            exit(65)
        }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("error: cannot encode output\n".utf8))
            exit(65)
        }

        print("\(result.width)x\(result.height) \(options.backend)")
    }

    private static func outputUTType(for ext: String) -> CFString? {
        switch ext.lowercased() {
        case "png": return UTType.png.identifier as CFString
        case "jpg", "jpeg": return UTType.jpeg.identifier as CFString
        default: return nil
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
