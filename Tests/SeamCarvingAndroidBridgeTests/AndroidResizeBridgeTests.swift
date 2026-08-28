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
}
