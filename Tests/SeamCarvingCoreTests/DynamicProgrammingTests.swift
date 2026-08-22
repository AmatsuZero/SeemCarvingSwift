import XCTest
@testable import SeamCarvingCore

final class DynamicProgrammingTests: XCTestCase {
    func testFindsKnownVerticalSeam() throws {
        let map = try EnergyMap(width: 3, height: 3, values: [
            1, 3, 0,
            2, 8, 9,
            5, 2, 6,
        ])
        let seam = try DynamicProgramming.findVerticalSeam(in: map)
        XCTAssertEqual(seam.coordinates, [0, 0, 1])
        XCTAssertEqual(seam.totalCost, 5, accuracy: 0.0001)
    }

    func testEqualCostsChooseSmallestPredecessorX() throws {
        let map = try EnergyMap(width: 3, height: 3, values: [Float](repeating: 1, count: 9))
        XCTAssertEqual(try DynamicProgramming.findVerticalSeam(in: map).coordinates, [0, 0, 0])
    }

    func testValidityPropertiesAcrossSizes() throws {
        for width in 1...12 {
            for height in 1...12 {
                let map = try Self.pseudoRandomMap(width: width, height: height, seed: UInt64(width * 100 + height))
                let seam = try DynamicProgramming.findVerticalSeam(in: map)
                XCTAssertEqual(seam.orientation, .vertical)
                XCTAssertEqual(seam.coordinates.count, height)
                for coord in seam.coordinates {
                    XCTAssertGreaterThanOrEqual(Int(coord), 0)
                    XCTAssertLessThan(Int(coord), width)
                }
                for i in 1..<height {
                    XCTAssertLessThanOrEqual(abs(Int(seam.coordinates[i]) - Int(seam.coordinates[i - 1])), 1)
                }
                let oracle = Self.slowVerticalSeamCost(map)
                XCTAssertEqual(seam.totalCost, oracle, accuracy: 0.001)
            }
        }
    }

    func testHardProtectedFullRowThrows() throws {
        var values = [Float](repeating: 1, count: 12)
        // Protect the entire second row (y=1).
        for x in 0..<3 {
            values[3 + x] = .infinity
        }
        let map = try EnergyMap(width: 3, height: 4, values: values)
        XCTAssertThrowsError(try DynamicProgramming.findVerticalSeam(in: map)) { error in
            XCTAssertEqual(error as? SeamCarvingError, .noFeasibleSeam)
        }
    }

    func testPartiallyProtectedRowRemainsSolvable() throws {
        var values = [Float](repeating: 1, count: 9)
        values[3] = .infinity  // y=1, x=0
        values[5] = .infinity  // y=1, x=2
        let map = try EnergyMap(width: 3, height: 3, values: values)
        let seam = try DynamicProgramming.findVerticalSeam(in: map)
        XCTAssertEqual(seam.coordinates[1], 1)
    }

    func testHorizontalSearchEqualsTransposePlusVertical() throws {
        let map = try Self.pseudoRandomMap(width: 5, height: 7, seed: 42)
        let horizontal = try DynamicProgramming.findSeam(in: map, orientation: .horizontal)
        XCTAssertEqual(horizontal.orientation, .horizontal)
        XCTAssertEqual(horizontal.coordinates.count, map.width)

        let transposed = try Self.transposed(map)
        let vertical = try DynamicProgramming.findVerticalSeam(in: transposed)
        XCTAssertEqual(horizontal.coordinates, vertical.coordinates)
        XCTAssertEqual(horizontal.totalCost, vertical.totalCost, accuracy: 0.0001)
    }

    // MARK: - Helpers

    static func pseudoRandomMap(width: Int, height: Int, seed: UInt64) throws -> EnergyMap {
        var state = seed
        var values = [Float]()
        values.reserveCapacity(width * height)
        for _ in 0..<(width * height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            values.append(Float(state % 1000) / 1000.0)
        }
        return try EnergyMap(width: width, height: height, values: values)
    }

    static func slowVerticalSeamCost(_ map: EnergyMap) -> Float {
        let w = map.width
        let h = map.height
        var cost = map.values
        for y in 1..<h {
            for x in 0..<w {
                let left = cost[(y - 1) * w + max(0, x - 1)]
                let center = cost[(y - 1) * w + x]
                let right = cost[(y - 1) * w + min(w - 1, x + 1)]
                cost[y * w + x] = map.values[y * w + x] + min(left, center, right)
            }
        }
        return cost[((h - 1) * w)..<(h * w)].min()!
    }

    static func transposed(_ map: EnergyMap) throws -> EnergyMap {
        let newWidth = map.height
        let newHeight = map.width
        var values = [Float](repeating: 0, count: newWidth * newHeight)
        for y in 0..<map.height {
            for x in 0..<map.width {
                values[x * newWidth + y] = map.values[y * map.width + x]
            }
        }
        return try EnergyMap(width: newWidth, height: newHeight, values: values)
    }
}
