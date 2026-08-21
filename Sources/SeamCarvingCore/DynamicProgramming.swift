public enum DynamicProgramming {
    /// Finds a minimum-cost vertical seam using two-row accumulation and Int8 parents.
    public static func findVerticalSeam(in map: EnergyMap) throws -> SeamPath {
        let width = map.width
        let height = map.height

        var previous = [Float](repeating: 0, count: width)
        var current = [Float](repeating: 0, count: width)
        var parents = [Int8](repeating: 0, count: width * height)

        for x in 0..<width {
            previous[x] = map.values[x]
        }

        for y in 1..<height {
            for x in 0..<width {
                let leftX = max(0, x - 1)
                let rightX = min(width - 1, x + 1)
                var bestCost = previous[leftX]
                var bestPred = leftX
                if leftX + 1 <= rightX {
                    for candidate in (leftX + 1)...rightX {
                        let cost = previous[candidate]
                        if cost < bestCost {
                            bestCost = cost
                            bestPred = candidate
                        }
                    }
                }
                current[x] = map.values[y * width + x] + bestCost
                parents[y * width + x] = Int8(bestPred - x)
            }
            swap(&previous, &current)
        }

        var minCost = Float.infinity
        var bestX = -1
        for x in 0..<width {
            if previous[x] < minCost {
                minCost = previous[x]
                bestX = x
            }
        }
        guard bestX >= 0, minCost.isFinite else {
            throw SeamCarvingError.noFeasibleSeam
        }

        var coordinates = [UInt32](repeating: 0, count: height)
        var x = bestX
        coordinates[height - 1] = UInt32(x)
        for y in stride(from: height - 1, through: 1, by: -1) {
            x += Int(parents[y * width + x])
            coordinates[y - 1] = UInt32(x)
        }

        return try SeamPath(orientation: .vertical, coordinates: coordinates, totalCost: minCost)
    }

    /// Finds a minimum-cost seam for the requested orientation. Horizontal search
    /// transposes the map, runs the vertical solver, and re-labels the orientation.
    public static func findSeam(in map: EnergyMap, orientation: SeamOrientation) throws -> SeamPath {
        switch orientation {
        case .vertical:
            return try findVerticalSeam(in: map)
        case .horizontal:
            let seam = try findVerticalSeam(in: transposed(map))
            return try SeamPath(orientation: .horizontal, coordinates: seam.coordinates, totalCost: seam.totalCost)
        }
    }

    private static func transposed(_ map: EnergyMap) throws -> EnergyMap {
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
