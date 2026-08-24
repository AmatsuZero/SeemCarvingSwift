import XCTest
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
@testable import SeamCarvingAppleRuntime

final class BackendSelectionTests: XCTestCase {
    func testRuntimeResizeUsesInjectedCPUBackend() async throws {
        let image = try RGBA8Image(width: 2, height: 2, pixels: [
            0, 0, 0, 255, 255, 0, 0, 255,
            0, 255, 0, 255, 0, 0, 255, 255,
        ])
        let carver = try AppleSeamCarver(configuration: .init(backend: .cpu, deterministic: true))
        let output = try await carver.resize(image, toPixelSize: try PixelSize(width: 1, height: 2))
        XCTAssertEqual(output.width, 1)
        XCTAssertEqual(output.height, 2)
    }

    func testAutomaticSelectsMetal() throws {
        let recorder = SelectionRecorder()
        let factory = recorder.makeFactory()
        let config = AppleSeamCarverConfiguration(backend: .automatic)
        _ = try AppleSeamCarver(configuration: config, factory: factory)
        XCTAssertEqual(recorder.selected, "metal")
    }

    func testAutomaticFallsBackToAccelerateWhenMetalFails() throws {
        let recorder = SelectionRecorder()
        recorder.metalError = SeamCarvingError.metalUnavailable
        let factory = recorder.makeFactory()
        _ = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .automatic), factory: factory)
        XCTAssertEqual(recorder.selected, "accelerate")
    }

    func testAutomaticFallsBackToCPUWhenMetalAndAccelerateFail() throws {
        let recorder = SelectionRecorder()
        recorder.metalError = SeamCarvingError.metalUnavailable
        recorder.accelerateError = SeamCarvingError.invalidConfiguration("no accelerate")
        let factory = recorder.makeFactory()
        _ = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .automatic), factory: factory)
        XCTAssertEqual(recorder.selected, "cpu")
    }

    func testExplicitAccelerateErrorNotSwallowed() throws {
        let recorder = SelectionRecorder()
        recorder.accelerateError = SeamCarvingError.invalidConfiguration("no accelerate")
        let factory = recorder.makeFactory()
        XCTAssertThrowsError(try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .accelerate), factory: factory))
    }

    func testExplicitMetalErrorNotSwallowed() throws {
        let recorder = SelectionRecorder()
        recorder.metalError = SeamCarvingError.metalUnavailable
        let factory = recorder.makeFactory()
        XCTAssertThrowsError(try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .metal), factory: factory))
    }

    func testCPUAlwaysSelectedForCPUAndDeterministic() throws {
        let recorder = SelectionRecorder()
        let factory = recorder.makeFactory()
        _ = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .cpu), factory: factory)
        XCTAssertEqual(recorder.selected, "cpu")

        recorder.selected = ""
        _ = try AppleSeamCarver(configuration: AppleSeamCarverConfiguration(backend: .automatic, deterministic: true), factory: factory)
        XCTAssertEqual(recorder.selected, "cpu")
    }
}

final class SelectionRecorder: @unchecked Sendable {
    var selected = ""
    var accelerateError: Error?
    var metalError: Error?

    func makeFactory() -> BackendFactory {
        var factory = BackendFactory.default
        factory.makeAccelerate = { [self] in
            selected = "accelerate"
            if let accelerateError { throw accelerateError }
            return FakeBackend(name: "accelerate")
        }
        factory.makeMetal = { [self] _ in
            selected = "metal"
            if let metalError { throw metalError }
            return FakeBackend(name: "metal")
        }
        factory.makeCPU = { [self] in
            selected = "cpu"
            return FakeBackend(name: "cpu")
        }
        return factory
    }
}

struct FakeBackend: SeamCarvingBackend {
    let name: String
    var identifier: String { name }

    func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath {
        throw SeamCarvingError.metalUnavailable
    }

    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image {
        throw SeamCarvingError.metalUnavailable
    }
}
