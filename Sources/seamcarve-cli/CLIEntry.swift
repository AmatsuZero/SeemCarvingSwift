#if os(macOS)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SeamCarvingCore
import SeamCarvingCLI
import SeamCarvingApple
import SeamCarvingVision

@main
enum CLIEntry {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            print("Usage: seamcarve-cli INPUT OUTPUT --width PIXELS --height PIXELS [--backend automatic|cpu|accelerate|metal] [--energy backward|forward] [--order width-first|height-first|adaptive] [--pre-scale none|lanczos-residual] [--deterministic] [--protect-mask PATH --protect-strength hard|soft --protect-weight VALUE] [--remove-mask PATH --removal-weight VALUE] [--face-policy caire|vision --face-cadence once|each-pass]")
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
            carver = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: options.backend, deterministic: options.deterministic))
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(70)
        }

        var masks = MaskPair()
        do {
            if let path = options.protectMaskPath {
                let mask = try loadMask(path: path)
                guard mask.width == inputImage.width, mask.height == inputImage.height else {
                    throw SeamCarvingError.invalidConfiguration("protection mask dimensions must match input")
                }
                masks = try MaskPair(
                    protectionLayers: [try ProtectionLayer(mask: mask, strength: options.protectStrength)],
                    removal: nil,
                    removalWeight: options.removalWeight
                )
            }
            if let path = options.removeMaskPath {
                let mask = try loadMask(path: path)
                guard mask.width == inputImage.width, mask.height == inputImage.height else {
                    throw SeamCarvingError.invalidConfiguration("removal mask dimensions must match input")
                }
                masks = try MaskPair(
                    protectionLayers: masks.protectionLayers,
                    removal: mask,
                    removalWeight: options.removalWeight
                )
            }
        } catch {
            FileHandle.standardError.write(Data("error: invalid mask: \(error)\n".utf8))
            exit(65)
        }

        var resizeOptions = ResizeOptions(
            energyMode: options.energy,
            dimensionOrder: options.dimensionOrder,
            masks: masks,
            preScaleStrategy: options.preScaleStrategy
        )
        resizeOptions.progress = { (progress: ResizeProgress) in
            FileHandle.standardError.write(Data("progress \(progress.completedEdits)/\(progress.totalEdits)\n".utf8))
        }

        let result: CGImage
        do {
            let target = try PixelSize(width: options.width, height: options.height)
            if let policy = options.facePolicy {
                let faceCarver = try FaceAwareSeamCarver(
                    configuration: AppleSeamCarverConfiguration(
                        backend: options.backend,
                        metalMode: .full,
                        deterministic: options.deterministic
                    ),
                    detector: try VisionFaceDetector(),
                    policy: policy,
                    cadence: options.faceCadence
                )
                result = try await faceCarver.resize(inputImage, orientation: .up, toPixelSize: target, options: resizeOptions)
            } else {
                result = try await carver.resize(inputImage, toPixelSize: target, options: resizeOptions)
            }
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

    private static func loadMask(path: String) throws -> Mask {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SeamCarvingError.invalidConfiguration("cannot decode mask at \(path)")
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
