import XCTest
@testable import SeamCarvingCore

final class ResizeTargetTests: XCTestCase {
    func testPercentageHalvesDimensions() throws {
        let target = try PixelSize(width: 100, height: 50).scaled(byPercentage: 50)
        XCTAssertEqual(target, try PixelSize(width: 50, height: 25))
    }

    func testPercentageRoundsHalfAwayFromZero() throws {
        let target = try PixelSize(width: 7, height: 9).scaled(byPercentage: 50)
        // 7 * 0.5 = 3.5 -> 4, 9 * 0.5 = 4.5 -> 5.
        XCTAssertEqual(target, try PixelSize(width: 4, height: 5))
    }

    func testPercentageClampsToMinimumOne() throws {
        let target = try PixelSize(width: 1, height: 3).scaled(byPercentage: 1)
        // 1 * 0.01 = 0.01 -> 0 -> clamped to 1; 3 * 0.01 = 0.03 -> 0 -> 1.
        XCTAssertEqual(target, try PixelSize(width: 1, height: 1))
    }

    func testPercentageAboveHundredEnlarges() throws {
        let target = try PixelSize(width: 10, height: 20).scaled(byPercentage: 150)
        XCTAssertEqual(target, try PixelSize(width: 15, height: 30))
    }

    func testPercentageNonPositiveRejected() {
        XCTAssertThrowsError(try PixelSize(width: 10, height: 10).scaled(byPercentage: 0))
        XCTAssertThrowsError(try PixelSize(width: 10, height: 10).scaled(byPercentage: -10))
    }

    func testSquareUsesShorterSide() throws {
        let expected = try PixelSize(width: 24, height: 24)
        XCTAssertEqual(try PixelSize(width: 32, height: 24).squareTarget(), expected)
        XCTAssertEqual(try PixelSize(width: 24, height: 32).squareTarget(), expected)
    }

    func testSquareOnAlreadySquareImage() throws {
        XCTAssertEqual(try PixelSize(width: 10, height: 10).squareTarget(), try PixelSize(width: 10, height: 10))
    }
}
