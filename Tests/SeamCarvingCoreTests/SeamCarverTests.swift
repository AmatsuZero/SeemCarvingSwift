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

    func testZeroTargetRejected() {
        XCTAssertThrowsError(try PixelSize(width: 0, height: 2)) { error in
            XCTAssertEqual(error as? SeamCarvingError, .invalidDimensions)
        }
    }

    func testEnlargementRejectedForShrinkOnly() async throws {
        let image = try Self.gradientImage(width: 3, height: 2)
        let target = try PixelSize(width: 5, height: 2)
        do {
            _ = try await SeamCarver().resize(image, to: target)
            XCTFail("expected throw")
        } catch let error as SeamCarvingError {
            XCTAssertEqual(error, .invalidTarget(source: try PixelSize(width: 3, height: 2), target: target))
        }
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
