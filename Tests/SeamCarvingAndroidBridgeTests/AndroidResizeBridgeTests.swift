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

    func testCancellationActionRunsOnlyOnceWhenCancellationSourcesRace() {
        let recorder = AndroidCancellationRecorder()
        let state = AndroidResizeOperationState()
        state.install(cancellationAction: {
            recorder.recordCancellation()
        })

        DispatchQueue.concurrentPerform(iterations: 32) { index in
            if index.isMultiple(of: 2) {
                state.cancelFromProgressCallback()
            } else {
                state.cancelAndWaitForProgressDelivery()
            }
        }

        XCTAssertEqual(recorder.cancellationCount, 1)
    }

    func testCancellationBeforeInstallCancelsInstalledTaskOnlyOnce() {
        let recorder = AndroidCancellationRecorder()
        let state = AndroidResizeOperationState()

        state.cancelAndWaitForProgressDelivery()
        state.cancelFromProgressCallback()
        XCTAssertEqual(recorder.cancellationCount, 0)

        state.install(cancellationAction: {
            recorder.recordCancellation()
        })
        state.cancelAndWaitForProgressDelivery()
        state.cancelFromProgressCallback()

        XCTAssertEqual(recorder.cancellationCount, 1)
    }

    func testCancellationDuringProgressWaitsAndCallbackStopDoesNotCancelAgain() {
        let recorder = AndroidCancellationRecorder()
        let state = AndroidResizeOperationState()
        state.install(cancellationAction: {
            recorder.recordCancellation()
        })
        XCTAssertTrue(state.beginProgressDelivery())

        let cancellationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            state.cancelAndWaitForProgressDelivery()
            cancellationFinished.signal()
        }

        XCTAssertEqual(recorder.waitForFirstCancellation(), .success)
        XCTAssertEqual(cancellationFinished.wait(timeout: .now() + 0.05), .timedOut)

        state.endProgressDelivery()
        state.cancelFromProgressCallback()

        XCTAssertEqual(cancellationFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(recorder.cancellationCount, 1)
        XCTAssertFalse(state.beginProgressDelivery())
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

private final class AndroidCancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let firstCancellation = DispatchSemaphore(value: 0)
    private var count = 0

    func recordCancellation() {
        lock.lock()
        count += 1
        let isFirstCancellation = count == 1
        lock.unlock()
        if isFirstCancellation {
            firstCancellation.signal()
        }
    }

    func waitForFirstCancellation() -> DispatchTimeoutResult {
        firstCancellation.wait(timeout: .now() + 1)
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
