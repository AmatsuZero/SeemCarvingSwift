import XCTest
@testable import SeamCarvingCore

final class SeamDebugArtifactsTests: XCTestCase {
    func testObserverReportsVerticalSeamInCurrentTopLeftCoordinates() async throws {
        let image = try Self.gradientImage(width: 5, height: 5)
        let protection = try Self.protectAllExceptVertical(width: 5, height: 5, seamX: 2)
        let recorder = ObservationRecorder()

        var options = ResizeOptions()
        options.masks = try MaskPair(
            protectionLayers: [try ProtectionLayer(mask: protection, strength: .hard)],
            removal: nil,
            removalWeight: 1_000
        )
        options.seamObserver = { observation in recorder.record(observation) }

        let result = try await SeamCarver().resize(
            image,
            to: try PixelSize(width: 4, height: 5),
            options: options
        )

        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 5)
        let observations = recorder.values
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0].index, 1)
        XCTAssertEqual(observations[0].totalCount, 1)
        XCTAssertEqual(observations[0].kind, .remove)
        XCTAssertEqual(observations[0].imageBeforeEdit.width, 5)
        XCTAssertEqual(observations[0].imageBeforeEdit.height, 5)
        XCTAssertEqual(observations[0].seam.orientation, .vertical)
        XCTAssertEqual(observations[0].seam.coordinates, [2, 2, 2, 2, 2])
    }

    func testObserverReportsHorizontalSeamInNonSquareCurrentTopLeftCoordinates() async throws {
        let image = try Self.gradientImage(width: 5, height: 4)
        let protection = try Self.protectAllExceptHorizontal(width: 5, height: 4, seamY: 1)
        let recorder = ObservationRecorder()

        var options = ResizeOptions()
        options.masks = try MaskPair(
            protectionLayers: [try ProtectionLayer(mask: protection, strength: .hard)],
            removal: nil,
            removalWeight: 1_000
        )
        options.seamObserver = { observation in recorder.record(observation) }

        let result = try await SeamCarver().resize(
            image,
            to: try PixelSize(width: 5, height: 3),
            options: options
        )

        XCTAssertEqual(result.width, 5)
        XCTAssertEqual(result.height, 3)
        let observations = recorder.values
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0].kind, .remove)
        XCTAssertEqual(observations[0].imageBeforeEdit.width, 5)
        XCTAssertEqual(observations[0].imageBeforeEdit.height, 4)
        XCTAssertEqual(observations[0].seam.orientation, .horizontal)
        XCTAssertEqual(observations[0].seam.coordinates, [1, 1, 1, 1, 1])
    }

    func testSeamObserverCancellationStopsBeforeEditProgress() async throws {
        let image = try Self.gradientImage(width: 5, height: 5)
        let recorder = ProgressRecorder()
        var options = ResizeOptions()
        options.seamObserver = { _ in throw CancellationError() }
        options.progress = { progress in recorder.record(progress.completedEdits) }

        do {
            _ = try await SeamCarver().resize(
                image,
                to: try PixelSize(width: 4, height: 5),
                options: options
            )
            XCTFail("expected cancellation from seam observer")
        } catch is CancellationError {
            XCTAssertEqual(recorder.values, [])
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private static func gradientImage(width: Int, height: Int) throws -> RGBA8Image {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8((x * 29 + y * 47) % 251)
                pixels.append(v)
                pixels.append(v)
                pixels.append(v)
                pixels.append(255)
            }
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    private static func protectAllExceptVertical(width: Int, height: Int, seamX: Int) throws -> Mask {
        var values = [Float](repeating: 1, count: width * height)
        for y in 0..<height {
            values[y * width + seamX] = 0
        }
        return try Mask(width: width, height: height, values: values)
    }

    private static func protectAllExceptHorizontal(width: Int, height: Int, seamY: Int) throws -> Mask {
        var values = [Float](repeating: 1, count: width * height)
        for x in 0..<width {
            values[seamY * width + x] = 0
        }
        return try Mask(width: width, height: height, values: values)
    }
}

private final class ObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [SeamObservation] = []

    func record(_ observation: SeamObservation) {
        lock.lock()
        observations.append(observation)
        lock.unlock()
    }

    var values: [SeamObservation] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }
}
