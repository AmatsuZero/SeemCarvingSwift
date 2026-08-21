public struct LuminancePlane: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) throws {
        guard width > 0, height > 0 else {
            throw SeamCarvingError.invalidDimensions
        }
        let expected = try checkedMultiply(width, height)
        guard values.count == expected else {
            throw SeamCarvingError.invalidConfiguration("luminance values count mismatch")
        }
        self.width = width
        self.height = height
        self.values = values
    }

    /// Computes the linear-light luma plane for an image.
    static func luma(of image: RGBA8Image) throws -> LuminancePlane {
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        var values = [Float](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let base = i * 4
            values[i] = linearLuma(
                r: image.pixels[base],
                g: image.pixels[base + 1],
                b: image.pixels[base + 2]
            )
        }
        return try LuminancePlane(width: width, height: height, values: values)
    }
}

public enum ForwardEnergy {
    /// Finds a minimum-cost vertical seam using the forward-luma recurrence with
    /// two-row accumulation and Int8 parents. The base row has zero disruption cost
    /// plus the optional per-pixel `adjustedBaseEnergy`.
    public static func findVerticalSeam(
        in luminance: LuminancePlane,
        adjustedBaseEnergy: EnergyMap? = nil
    ) throws -> SeamPath {
        let width = luminance.width
        let height = luminance.height

        if let base = adjustedBaseEnergy {
            guard base.width == width, base.height == height else {
                throw SeamCarvingError.invalidConfiguration("adjusted base energy dimensions mismatch")
            }
        }

        func sample(_ x: Int, _ y: Int) -> Float {
            let sx = min(max(x, 0), width - 1)
            let sy = min(max(y, 0), height - 1)
            return luminance.values[sy * width + sx]
        }

        func base(_ x: Int, _ y: Int) -> Float {
            adjustedBaseEnergy?.values[y * width + x] ?? 0
        }

        var previous = [Float](repeating: 0, count: width)
        var current = [Float](repeating: 0, count: width)
        var parents = [Int8](repeating: 0, count: width * height)

        for x in 0..<width {
            previous[x] = base(x, 0)
        }

        for y in 1..<height {
            for x in 0..<width {
                let cu = abs(sample(x + 1, y) - sample(x - 1, y))
                let cl = cu + abs(sample(x, y - 1) - sample(x - 1, y))
                let cr = cu + abs(sample(x, y - 1) - sample(x + 1, y))

                var bestCost = Float.infinity
                var bestPred = x
                if x > 0 {
                    let cost = previous[x - 1] + cl
                    if cost < bestCost {
                        bestCost = cost
                        bestPred = x - 1
                    }
                }
                let upCost = previous[x] + cu
                if upCost < bestCost {
                    bestCost = upCost
                    bestPred = x
                }
                if x < width - 1 {
                    let cost = previous[x + 1] + cr
                    if cost < bestCost {
                        bestCost = cost
                        bestPred = x + 1
                    }
                }

                current[x] = base(x, y) + bestCost
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

    /// Finds a forward-energy seam for the requested orientation. Horizontal search
    /// transposes both the luminance plane and any base energy, then re-labels.
    public static func findSeam(
        in luminance: LuminancePlane,
        orientation: SeamOrientation,
        adjustedBaseEnergy: EnergyMap? = nil
    ) throws -> SeamPath {
        switch orientation {
        case .vertical:
            return try findVerticalSeam(in: luminance, adjustedBaseEnergy: adjustedBaseEnergy)
        case .horizontal:
            let transposedLuma = try transposed(luminance)
            let transposedBase = try adjustedBaseEnergy.map { try transposed($0) }
            let seam = try findVerticalSeam(in: transposedLuma, adjustedBaseEnergy: transposedBase)
            return try SeamPath(orientation: .horizontal, coordinates: seam.coordinates, totalCost: seam.totalCost)
        }
    }

    private static func transposed(_ plane: LuminancePlane) throws -> LuminancePlane {
        let newWidth = plane.height
        let newHeight = plane.width
        var values = [Float](repeating: 0, count: newWidth * newHeight)
        for y in 0..<plane.height {
            for x in 0..<plane.width {
                values[x * newWidth + y] = plane.values[y * plane.width + x]
            }
        }
        return try LuminancePlane(width: newWidth, height: newHeight, values: values)
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
