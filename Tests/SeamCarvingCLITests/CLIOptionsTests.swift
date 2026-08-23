import XCTest
@testable import SeamCarvingCLI
import SeamCarvingVision

final class CLIOptionsTests: XCTestCase {
    func testDocumentedExample() throws {
        let options = try CLIOptions.parse([
            "input.png", "output.png",
            "--width", "20", "--height", "18",
            "--backend", "automatic", "--energy", "backward",
        ])
        XCTAssertEqual(options.inputPath, "input.png")
        XCTAssertEqual(options.outputPath, "output.png")
        XCTAssertEqual(options.resizeMode, .exact(width: 20, height: 18))
        XCTAssertEqual(options.backend, .automatic)
        XCTAssertEqual(options.energy, .backwardSobel)
    }

    func testMissingPathsThrow() {
        XCTAssertThrowsError(try CLIOptions.parse(["--width", "20", "--height", "18"]))
    }

    func testInvalidDimensionsThrow() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "0", "--height", "18"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "abc", "--height", "18"]))
    }

    func testMissingOneDimensionThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--height", "18"]))
    }

    func testUnknownBackendThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--backend", "gpu"]))
    }

    func testUnknownEnergyThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--energy", "sideways"]))
    }

    func testForwardEnergyParses() throws {
        let options = try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--energy", "forward", "--backend", "metal"])
        XCTAssertEqual(options.energy, .forwardLuma)
        XCTAssertEqual(options.backend, .metal)
    }

    func testAdvancedOptionsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--order", "adaptive", "--pre-scale", "lanczos-residual", "--deterministic"
        ])
        XCTAssertEqual(options.dimensionOrder, .adaptiveNormalizedCost)
        XCTAssertEqual(options.preScaleStrategy, .lanczosThenExactResidual)
        XCTAssertTrue(options.deterministic)
    }

    func testMaskOptionsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--protect-mask", "protect.png", "--protect-strength", "hard",
            "--remove-mask", "remove.png", "--removal-weight", "2500"
        ])
        XCTAssertEqual(options.protectMaskPath, "protect.png")
        XCTAssertEqual(options.removeMaskPath, "remove.png")
        XCTAssertEqual(options.protectStrength, .hard)
        XCTAssertEqual(options.removalWeight, 2500)
    }

    func testFaceOptionsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--face-policy", "vision", "--face-cadence", "each-pass"
        ])
        XCTAssertEqual(options.facePolicy, .visionQuality(try VisionQualityParameters()))
        XCTAssertEqual(options.faceCadence, .redetectEveryPass)
    }

    // MARK: - Negative: unknown flags and duplicate positionals

    func testUnknownFlagThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--nonsense"]))
    }

    func testDuplicatePositionalThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "extra", "--width", "20", "--height", "18"]))
    }

    // MARK: - Negative: illegal numeric values

    func testIllegalFloatValuesThrow() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--percentage", "abc"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--percentage", "-5"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--blur-radius", "abc"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--blur-radius", "-1"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--sobel-threshold", "nan"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--sobel-threshold", "-0.5"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--protect-weight", "abc"]))
    }

    // MARK: - Negative: conflicting resize modes

    func testSquareConflictsWithExactDimensions() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--square", "--width", "20", "--height", "18"]))
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--square", "--width", "20"]))
    }

    func testPercentageConflictsWithExactDimensions() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--percentage", "50", "--width", "20", "--height", "18"]))
    }

    func testSquareConflictsWithPercentage() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--square", "--percentage", "50"]))
    }

    // MARK: - Reserved typed fields

    func testPercentageModeParses() throws {
        let options = try CLIOptions.parse(["in", "out", "--percentage", "50"])
        XCTAssertEqual(options.resizeMode, .percentage(50))
    }

    func testSquareModeParses() throws {
        let options = try CLIOptions.parse(["in", "out", "--square"])
        XCTAssertEqual(options.resizeMode, .square)
    }

    func testWidthHeightCompatibility() throws {
        let exact = try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18"])
        XCTAssertEqual(exact.width, 20)
        XCTAssertEqual(exact.height, 18)

        let percentage = try CLIOptions.parse(["in", "out", "--percentage", "50"])
        XCTAssertNil(percentage.width)
        XCTAssertNil(percentage.height)

        let square = try CLIOptions.parse(["in", "out", "--square"])
        XCTAssertNil(square.width)
        XCTAssertNil(square.height)
    }

    func testEnergyControlsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--blur-radius", "2", "--sobel-threshold", "0.3"
        ])
        XCTAssertEqual(options.blurRadius, 2)
        XCTAssertEqual(options.sobelThreshold, 0.3)
    }

    func testFormatFlagParses() throws {
        XCTAssertEqual(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--format", "png"]).outputFormat, .png)
        XCTAssertEqual(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--format", "jpeg"]).outputFormat, .jpeg)
        XCTAssertEqual(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--format", "jpg"]).outputFormat, .jpeg)
        XCTAssertEqual(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--format", "BMP"]).outputFormat, .bmp)
    }

    func testInvalidFormatThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--format", "tiff"]))
    }

    func testReservedDebugOptionsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--debug", "--debug-directory", "seams",
            "--seam-color", "#ff0000", "--seam-shape", "points"
        ])
        XCTAssertTrue(options.debug)
        XCTAssertEqual(options.debugDirectory, "seams")
        XCTAssertEqual(options.seamColor, SeamColor(red: 255, green: 0, blue: 0, alpha: 255))
        XCTAssertEqual(options.seamShape, .points)
    }

    func testReservedBatchOptionsParse() throws {
        let options = try CLIOptions.parse([
            "in", "out", "--width", "20", "--height", "18",
            "--input-dir", "src", "--output-dir", "dst", "--recursive", "--concurrency", "4"
        ])
        XCTAssertEqual(options.inputDirectory, "src")
        XCTAssertEqual(options.outputDirectory, "dst")
        XCTAssertTrue(options.recursive)
        XCTAssertEqual(options.concurrency, 4)
    }

    func testInvalidConcurrencyThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--concurrency", "0"]))
    }

    func testInvalidSeamShapeThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--seam-shape", "curves"]))
    }

    func testInvalidSeamColorThrows() {
        XCTAssertThrowsError(try CLIOptions.parse(["in", "out", "--width", "20", "--height", "18", "--seam-color", "red"]))
    }

    // MARK: - SeamColor hex parsing

    func testSeamColorHexParsing() {
        XCTAssertEqual(SeamColor(hexString: "ff0000"), SeamColor(red: 255, green: 0, blue: 0, alpha: 255))
        XCTAssertEqual(SeamColor(hexString: "#00ff00"), SeamColor(red: 0, green: 255, blue: 0, alpha: 255))
        XCTAssertEqual(SeamColor(hexString: "0000ffff"), SeamColor(red: 0, green: 0, blue: 255, alpha: 255))
        XCTAssertEqual(SeamColor(hexString: "0000ff80"), SeamColor(red: 0, green: 0, blue: 255, alpha: 128))
        XCTAssertNil(SeamColor(hexString: "ff00"))
        XCTAssertNil(SeamColor(hexString: "gg0000"))
    }

    // MARK: - Exit code mapping

    func testExitCodeMapping() {
        XCTAssertEqual(CLIExitCode.exitCode(for: CLIParseError.invalidArguments), .usage)
        XCTAssertEqual(CLIExitCode.exitCode(for: CLIParseError.conflictingModes), .usage)
        XCTAssertEqual(CLIExitCode.exitCode(for: CLIConfigurationError.reservedOptionNotImplemented("--debug")), .usage)
        XCTAssertEqual(CLIExitCode.exitCode(for: CLIImageIOError.cannotDecodeInput), .dataError)
        XCTAssertEqual(CLIExitCode.exitCode(for: CLIImageIOError.unsupportedOutputFormat("bmp")), .dataError)
        XCTAssertEqual(CLIExitCode.exitCode(for: CancellationError()), .cancelled)
    }
}
