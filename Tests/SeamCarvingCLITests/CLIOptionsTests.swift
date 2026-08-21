import XCTest
@testable import SeamCarvingCLI

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
}
