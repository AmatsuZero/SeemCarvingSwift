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
        XCTAssertEqual(options.width, 20)
        XCTAssertEqual(options.height, 18)
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
}
