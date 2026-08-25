import XCTest
@testable import SeamCarvingAndroidBridge

final class BridgeProbeTests: XCTestCase {
    func testEchoPreservesEveryByte() {
        XCTAssertEqual(BridgeProbe.echo([0, 1, 127, 255]), [0, 1, 127, 255])
    }
}
