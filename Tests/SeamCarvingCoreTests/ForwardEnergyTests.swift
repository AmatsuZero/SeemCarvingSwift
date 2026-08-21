import XCTest
@testable import SeamCarvingCore

final class ForwardEnergyTests: XCTestCase {
    func testForwardFindsKnownSeam() throws {
        // Center peak exercises clamp-to-edge at x=0 and x=width-1 on row y=1.
        let luma = try LuminancePlane(width: 3, height: 3, values: [
            0, 0, 0,
            0, 1, 0,
            0, 0, 0,
        ])
        let seam = try ForwardEnergy.findVerticalSeam(in: luma)
        XCTAssertEqual(seam.coordinates, [0, 1, 0])
        XCTAssertEqual(seam.totalCost, 0, accuracy: 0.0001)
    }

    func testForwardMatchesSlowOracle() throws {
        for width in 1...8 {
            for height in 1...8 {
                let luma = try Self.pseudoRandomLuma(width: width, height: height, seed: UInt64(width * 17 + height))
                let seam = try ForwardEnergy.findVerticalSeam(in: luma)
                let oracle = Self.slowForwardVerticalSeam(luma)
                XCTAssertEqual(seam.coordinates, oracle.coordinates, "mismatch at \(width)x\(height)")
                XCTAssertEqual(seam.totalCost, oracle.cost, accuracy: 0.001, "cost mismatch at \(width)x\(height)")
            }
        }
    }

    func testHorizontalForwardEqualsTransposePlusVertical() throws {
        let luma = try Self.pseudoRandomLuma(width: 5, height: 4, seed: 99)
        let horizontal = try ForwardEnergy.findSeam(in: luma, orientation: .horizontal)
        XCTAssertEqual(horizontal.orientation, .horizontal)
        XCTAssertEqual(horizontal.coordinates.count, luma.width)

        let transposed = try Self.transposed(luma)
        let vertical = try ForwardEnergy.findVerticalSeam(in: transposed)
        XCTAssertEqual(horizontal.coordinates, vertical.coordinates)
        XCTAssertEqual(horizontal.totalCost, vertical.totalCost, accuracy: 0.0001)
    }

    func testLineAndSinglePixelImages() throws {
        let column = try LuminancePlane(width: 1, height: 3, values: [0.2, 0.9, 0.1])
        XCTAssertEqual(try ForwardEnergy.findVerticalSeam(in: column).coordinates, [0, 0, 0])

        let single = try LuminancePlane(width: 1, height: 1, values: [0.5])
        XCTAssertEqual(try ForwardEnergy.findVerticalSeam(in: single).coordinates, [0])
    }

    // MARK: - Helpers

    static func pseudoRandomLuma(width: Int, height: Int, seed: UInt64) throws -> LuminancePlane {
        var state = seed
        var values = [Float]()
        values.reserveCapacity(width * height)
        for _ in 0..<(width * height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            values.append(Float(state % 1000) / 1000.0)
        }
        return try LuminancePlane(width: width, height: height, values: values)
    }

    static func transposed(_ luma: LuminancePlane) throws -> LuminancePlane {
        let newWidth = luma.height
        let newHeight = luma.width
        var values = [Float](repeating: 0, count: newWidth * newHeight)
        for y in 0..<luma.height {
            for x in 0..<luma.width {
                values[x * newWidth + y] = luma.values[y * luma.width + x]
            }
        }
        return try LuminancePlane(width: newWidth, height: newHeight, values: values)
    }

    /// Full-matrix reference implementation of the CU/CL/CR forward recurrence.
    static func slowForwardVerticalSeam(_ luma: LuminancePlane) -> (coordinates: [UInt32], cost: Float) {
        let w = luma.width
        let h = luma.height

        func sample(_ x: Int, _ y: Int) -> Float {
            let sx = min(max(x, 0), w - 1)
            let sy = min(max(y, 0), h - 1)
            return luma.values[sy * w + sx]
        }

        var m = [Float](repeating: 0, count: w * h)
        var parent = [Int8](repeating: 0, count: w * h)
        for y in 1..<h {
            for x in 0..<w {
                let cu = abs(sample(x + 1, y) - sample(x - 1, y))
                let cl = cu + abs(sample(x, y - 1) - sample(x - 1, y))
                let cr = cu + abs(sample(x, y - 1) - sample(x + 1, y))
                var bestCost = Float.infinity
                var bestPred = x
                if x > 0 {
                    let cost = m[(y - 1) * w + (x - 1)] + cl
                    if cost < bestCost { bestCost = cost; bestPred = x - 1 }
                }
                let upCost = m[(y - 1) * w + x] + cu
                if upCost < bestCost { bestCost = upCost; bestPred = x }
                if x < w - 1 {
                    let cost = m[(y - 1) * w + (x + 1)] + cr
                    if cost < bestCost { bestCost = cost; bestPred = x + 1 }
                }
                m[y * w + x] = bestCost
                parent[y * w + x] = Int8(bestPred - x)
            }
        }

        var minCost = Float.infinity
        var bestX = -1
        for x in 0..<w {
            if m[(h - 1) * w + x] < minCost {
                minCost = m[(h - 1) * w + x]
                bestX = x
            }
        }
        var coordinates = [UInt32](repeating: 0, count: h)
        var x = bestX
        coordinates[h - 1] = UInt32(x)
        for y in stride(from: h - 1, through: 1, by: -1) {
            x += Int(parent[y * w + x])
            coordinates[y - 1] = UInt32(x)
        }
        return (coordinates, minCost)
    }
}
