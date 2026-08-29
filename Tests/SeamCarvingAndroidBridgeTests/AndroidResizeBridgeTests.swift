import XCTest
@testable import SeamCarvingAndroidBridge

final class AndroidResizeBridgeTests: XCTestCase {
    func testResizeTwoByTwoFixtureToOneByTwo() async throws {
        let result = try await AndroidResizeBridge.resize(
            width: 2,
            height: 2,
            bytes: [
                0, 0, 0, 255,
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
            ],
            targetWidth: 1,
            targetHeight: 2,
            protectionMask: [],
            removalMask: []
        )

        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.bytes, [
            0, 0, 0, 255,
            0, 255, 0, 255,
        ])
    }

    func testOperationReportsEveryCompletedEditAndCurrentSize() async throws {
        let recorder = AndroidProgressRecorder()
        let operation = AndroidResizeOperation()

        _ = try await operation.resize(
            width: 4,
            height: 3,
            bytes: Self.gradientBytes(width: 4, height: 3),
            targetWidth: 2,
            targetHeight: 2,
            protectionMask: [],
            removalMask: [],
            progress: { completed, total, width, height in
                recorder.record((completed, total, width, height))
                return true
            }
        )

        XCTAssertEqual(
            recorder.values.map { [$0.0, $0.1, $0.2, $0.3] },
            [
                [1, 3, 3, 3],
                [2, 3, 2, 3],
                [3, 3, 2, 2],
            ]
        )
    }

    func testOperationCancelsWhenProgressConsumerStops() async throws {
        let recorder = AndroidProgressRecorder()
        let operation = AndroidResizeOperation()

        do {
            _ = try await operation.resize(
                width: 96,
                height: 64,
                bytes: Self.gradientBytes(width: 96, height: 64),
                targetWidth: 1,
                targetHeight: 64,
                protectionMask: [],
                removalMask: [],
                progress: { completed, total, width, height in
                    recorder.record((completed, total, width, height))
                    return false
                }
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(recorder.values.count, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private static func gradientBytes(width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8((x * 61 + y * 37) % 256)
                bytes.append(contentsOf: [value, value, value, 255])
            }
        }
        return bytes
    }
}

private final class AndroidProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [(Int32, Int32, Int32, Int32)] = []

    func record(_ value: (Int32, Int32, Int32, Int32)) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }

    var values: [(Int32, Int32, Int32, Int32)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}
