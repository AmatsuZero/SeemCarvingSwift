import ArgumentParser
import Foundation
import SeamCarvingCore
import SeamCarvingVision

/// The swift-argument-parser backed syntax layer for `seamcarve-cli`.
///
/// Keep this type focused on argv syntax, primitive type conversion, and enum
/// spelling. Cross-field/business validation remains in `CLIOptions`,
/// `CLIConfiguration`, and `CLIProcessor` so the command parser does not own
/// image-processing behavior.
public struct CLIParsedArguments: ParsableArguments, Sendable {
    @Argument(help: "Input image path, http(s) URL, or '-' for stdin.")
    public var inputPath: String?

    @Argument(help: "Output image path or '-' for stdout.")
    public var outputPath: String?

    @Option(name: .long, help: "Exact output width in pixels.")
    public var width: Int?

    @Option(name: .long, help: "Exact output height in pixels.")
    public var height: Int?

    @Option(name: .long, help: "Scale both dimensions by this positive percentage.")
    public var percentage: Float?

    @Flag(name: .long, help: "Resize to a square using the source short edge.")
    public var square = false

    @Option(name: .long, help: "Backend: automatic, cpu, accelerate, or metal.")
    public var backend: BackendArgument = .automatic

    @Option(name: .long, help: "Energy: backward or forward.")
    public var energy: EnergyArgument = .backward

    @Option(name: .customLong("order"), help: "Dimension order: width-first, height-first, or adaptive.")
    public var dimensionOrder: DimensionOrderArgument = .widthFirst

    @Option(name: .customLong("pre-scale"), help: "Pre-scale strategy: none or lanczos-residual.")
    public var preScaleStrategy: PreScaleArgument = .none

    @Flag(name: .long, help: "Use deterministic backend behavior where supported.")
    public var deterministic = false

    @Option(name: .customLong("protect-mask"), help: "Protection mask image path.")
    public var protectMaskPath: String?

    @Option(name: .customLong("remove-mask"), help: "Removal mask image path.")
    public var removeMaskPath: String?

    @Option(name: .customLong("protect-strength"), help: "Protection strength: hard or soft.")
    public var protectStrength: ProtectStrengthArgument = .soft

    @Option(name: .customLong("protect-weight"), help: "Non-negative soft protection weight.")
    public var protectWeight: Float = 1_000

    @Option(name: .customLong("removal-weight"), help: "Non-negative removal weight.")
    public var removalWeight: Float = 1_000

    @Option(name: .customLong("face-policy"), help: "Face policy: caire or vision.")
    public var facePolicy: FacePolicyArgument?

    @Option(name: .customLong("face-cadence"), help: "Face cadence: once or each-pass.")
    public var faceCadence: FaceCadenceArgument = .once

    @Option(name: .customLong("blur-radius"), help: "Non-negative luma blur radius for backward Sobel energy.")
    public var blurRadius: Int?

    @Option(name: .customLong("sobel-threshold"), help: "Non-negative Sobel threshold for backward energy.")
    public var sobelThreshold: Float?

    @Option(name: .customLong("format"), help: "Output format: png, jpeg, jpg, or bmp.")
    public var outputFormat: OutputFormatArgument?

    @Flag(name: .long, help: "Write seam/debug artifacts.")
    public var debug = false

    @Option(name: .customLong("debug-directory"), help: "Directory for debug artifacts.")
    public var debugDirectory: String?

    @Option(name: .customLong("seam-color"), help: "Seam overlay color as RRGGBB/RRGGBBAA, with optional '#'.")
    public var seamColor: SeamColorArgument?

    @Option(name: .customLong("seam-shape"), help: "Seam visualization shape: line or points.")
    public var seamShape: SeamShapeArgument?

    @Option(name: .customLong("input-dir"), help: "Batch input directory.")
    public var inputDirectory: String?

    @Option(name: .customLong("output-dir"), help: "Batch output directory.")
    public var outputDirectory: String?

    @Flag(name: .long, help: "Recurse into the batch input directory.")
    public var recursive = false

    @Option(name: .long, help: "Positive batch concurrency limit.")
    public var concurrency: Int?

    public init() {}

    public func makeOptions(inputPath overrideInputPath: String? = nil, outputPath overrideOutputPath: String? = nil) throws -> CLIOptions {
        guard let inputPath = overrideInputPath ?? self.inputPath,
              let outputPath = overrideOutputPath ?? self.outputPath else {
            throw CLIParseError.invalidArguments
        }
        guard width == nil || width! > 0 else { throw CLIParseError.invalidArguments }
        guard height == nil || height! > 0 else { throw CLIParseError.invalidArguments }
        guard percentage == nil || (percentage!.isFinite && percentage! > 0) else { throw CLIParseError.invalidArguments }
        guard protectWeight.isFinite && protectWeight >= 0 else { throw CLIParseError.invalidArguments }
        guard removalWeight.isFinite && removalWeight >= 0 else { throw CLIParseError.invalidArguments }
        guard blurRadius == nil || blurRadius! >= 0 else { throw CLIParseError.invalidArguments }
        guard sobelThreshold == nil || (sobelThreshold!.isFinite && sobelThreshold! >= 0) else {
            throw CLIParseError.invalidArguments
        }
        guard concurrency == nil || concurrency! > 0 else { throw CLIParseError.invalidArguments }

        let resizeMode = try resolveResizeMode()
        let protectionStrength: MaskStrength
        switch protectStrength {
        case .hard:
            protectionStrength = .hard
        case .soft:
            protectionStrength = .soft(protectWeight)
        }

        return CLIOptions(
            inputPath: inputPath,
            outputPath: outputPath,
            resizeMode: resizeMode,
            backend: backend.domainValue,
            energy: energy.domainValue,
            dimensionOrder: dimensionOrder.domainValue,
            preScaleStrategy: preScaleStrategy.domainValue,
            deterministic: deterministic,
            protectMaskPath: protectMaskPath,
            removeMaskPath: removeMaskPath,
            protectStrength: protectionStrength,
            protectWeight: protectWeight,
            removalWeight: removalWeight,
            facePolicy: try facePolicy?.domainValue(),
            faceCadence: faceCadence.domainValue,
            blurRadius: blurRadius,
            sobelThreshold: sobelThreshold,
            outputFormat: outputFormat?.domainValue,
            debug: debug,
            debugDirectory: debugDirectory,
            seamColor: seamColor?.domainValue,
            seamShape: seamShape?.domainValue,
            inputDirectory: inputDirectory,
            outputDirectory: outputDirectory,
            recursive: recursive,
            concurrency: concurrency
        )
    }

    private func resolveResizeMode() throws -> ResizeMode {
        let hasExact = width != nil || height != nil
        if square {
            guard !hasExact, percentage == nil else { throw CLIParseError.conflictingModes }
            return .square
        }
        if let percentage {
            guard !hasExact else { throw CLIParseError.conflictingModes }
            return .percentage(percentage)
        }
        guard let width, let height else { throw CLIParseError.invalidArguments }
        return .exact(width: width, height: height)
    }
}

public enum CLIArgumentParser {
    public static func parseOptions(_ arguments: [String]) throws -> CLIOptions {
        try parse(arguments).makeOptions()
    }

    public static func parse(_ arguments: [String]) throws -> CLIParsedArguments {
        do {
            return try CLIParsedArguments.parse(arguments)
        } catch let error as CLIParseError {
            throw error
        } catch {
            throw CLIParseError.invalidArguments
        }
    }
}

public enum BackendArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case automatic
    case cpu
    case accelerate
    case metal

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: BackendPreference {
        switch self {
        case .automatic: return .automatic
        case .cpu: return .cpu
        case .accelerate: return .accelerate
        case .metal: return .metal
        }
    }
}

public enum EnergyArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case backward
    case forward

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: EnergyMode {
        switch self {
        case .backward: return .backwardSobel
        case .forward: return .forwardLuma
        }
    }
}

public enum DimensionOrderArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case widthFirst = "width-first"
    case heightFirst = "height-first"
    case adaptive

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: DimensionOrder {
        switch self {
        case .widthFirst: return .widthThenHeight
        case .heightFirst: return .heightThenWidth
        case .adaptive: return .adaptiveNormalizedCost
        }
    }
}

public enum PreScaleArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case none
    case lanczosResidual = "lanczos-residual"

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: PreScaleStrategy {
        switch self {
        case .none: return .none
        case .lanczosResidual: return .lanczosThenExactResidual
        }
    }
}

public enum ProtectStrengthArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case hard
    case soft

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

public enum FacePolicyArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case caire
    case vision

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    func domainValue() throws -> FaceProtectionPolicy {
        switch self {
        case .caire: return .caireInspired(try CaireInspiredParameters())
        case .vision: return .visionQuality(try VisionQualityParameters())
        }
    }
}

public enum FaceCadenceArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case once
    case eachPass = "each-pass"

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: FaceDetectionCadence {
        switch self {
        case .once: return .detectOnceAndTransformMask
        case .eachPass: return .redetectEveryPass
        }
    }
}

public enum OutputFormatArgument: ExpressibleByArgument, Sendable, Equatable {
    case png
    case jpeg
    case bmp

    public init?(argument: String) {
        guard let value = CLIOutputFormat.parse(argument) else { return nil }
        switch value {
        case .png: self = .png
        case .jpeg: self = .jpeg
        case .bmp: self = .bmp
        }
    }

    var domainValue: CLIOutputFormat {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .bmp: return .bmp
        }
    }
}

public struct SeamColorArgument: ExpressibleByArgument, Sendable, Equatable {
    public let domainValue: SeamColor

    public init?(argument: String) {
        guard let color = SeamColor(hexString: argument) else { return nil }
        self.domainValue = color
    }
}

public enum SeamShapeArgument: String, ExpressibleByArgument, Sendable, Equatable {
    case line
    case points

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }

    var domainValue: SeamShape {
        switch self {
        case .line: return .line
        case .points: return .points
        }
    }
}
