import XCTest
@testable import SeamCarvingCore

final class SeamCarverTests: XCTestCase {
    func testShrinkToSmallerDimensions() async throws {
        let image = try Self.gradientImage(width: 4, height: 3)
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 2, height: 2))
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
    }

    func testNoOpResize() async throws {
        let image = try Self.gradientImage(width: 3, height: 2)
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 3, height: 2))
        XCTAssertEqual(result, image)
    }

    func testNonePreScaleStrategyMatchesDefault() async throws {
        // `.none` must preserve the existing exact, mask-aware seam-carving
        // semantics — it is the default and must reach the requested dimensions.
        let image = try Self.gradientImage(width: 4, height: 3)
        let target = try PixelSize(width: 2, height: 2)

        var explicit = ResizeOptions()
        explicit.preScaleStrategy = .none
        let explicitResult = try await SeamCarver().resize(image, to: target, options: explicit)

        let defaultResult = try await SeamCarver().resize(image, to: target)

        XCTAssertEqual(explicitResult, defaultResult)
        XCTAssertEqual(explicitResult.width, target.width)
        XCTAssertEqual(explicitResult.height, target.height)
    }

    func testZeroTargetRejected() {
        XCTAssertThrowsError(try PixelSize(width: 0, height: 2)) { error in
            XCTAssertEqual(error as? SeamCarvingError, .invalidDimensions)
        }
    }

    func testEnlargementSupported() async throws {
        let image = try Self.gradientImage(width: 3, height: 2)
        let result = try await SeamCarver().resize(image, to: try PixelSize(width: 5, height: 2))
        XCTAssertEqual(result.width, 5)
        XCTAssertEqual(result.height, 2)
    }

    func testProgressSequence() async throws {
        let image = try Self.gradientImage(width: 4, height: 3)
        let recorder = ProgressRecorder()
        var options = ResizeOptions()
        options.progress = { progress in recorder.record(progress.completedEdits) }
        _ = try await SeamCarver().resize(image, to: try PixelSize(width: 2, height: 2), options: options)
        XCTAssertEqual(recorder.values, [1, 2, 3])
    }

    func testCancellationOfPreCancelledTask() async throws {
        let image = try Self.gradientImage(width: 4, height: 3)
        let target = try PixelSize(width: 2, height: 2)
        let task = Task {
            try await SeamCarver().resize(image, to: target)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testForwardEnergyRejectsInvalidControls() async throws {
        let image = try Self.gradientImage(width: 4, height: 3)
        let target = try PixelSize(width: 2, height: 2)

        var negativeBlur = ResizeOptions()
        negativeBlur.energyMode = .forwardLuma
        negativeBlur.blurRadius = -1
        do {
            _ = try await SeamCarver().resize(image, to: target, options: negativeBlur)
            XCTFail("expected negative blur radius rejection")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .invalidConfiguration("blur radius must be nonnegative"))
        }

        var nanThreshold = ResizeOptions()
        nanThreshold.energyMode = .forwardLuma
        nanThreshold.sobelThreshold = .nan
        do {
            _ = try await SeamCarver().resize(image, to: target, options: nanThreshold)
            XCTFail("expected NaN Sobel threshold rejection")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .invalidConfiguration("Sobel threshold must be finite and nonnegative"))
        }

        var negativeThreshold = ResizeOptions()
        negativeThreshold.energyMode = .forwardLuma
        negativeThreshold.sobelThreshold = -0.5
        do {
            _ = try await SeamCarver().resize(image, to: target, options: negativeThreshold)
            XCTFail("expected negative Sobel threshold rejection")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .invalidConfiguration("Sobel threshold must be finite and nonnegative"))
        }
    }

    // MARK: - Helpers

    static func gradientImage(width: Int, height: Int) throws -> RGBA8Image {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 61 + y * 37) % 256)
                pixels.append(v)
                pixels.append(v)
                pixels.append(v)
                pixels.append(255)
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []

    func record(_ value: Int) {
        lock.lock()
        _values.append(value)
        lock.unlock()
    }

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}
