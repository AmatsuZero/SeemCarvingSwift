public enum SeamEditor {
    /// Removes a seam from an image. Horizontal seams are handled by transposing,
    /// converting to a vertical seam, removing, and transposing back.
    public static func remove(_ seam: SeamPath, from image: RGBA8Image) throws -> RGBA8Image {
        switch seam.orientation {
        case .vertical:
            return try removeVertical(seam, from: image)
        case .horizontal:
            let transposedImage = try transpose(image)
            let verticalSeam = try SeamPath(orientation: .vertical, coordinates: seam.coordinates, totalCost: seam.totalCost)
            let result = try removeVertical(verticalSeam, from: transposedImage)
            return try transpose(result)
        }
    }

    /// Removes a seam from a mask, mirroring the image edit coordinate-for-coordinate.
    public static func remove(_ seam: SeamPath, from mask: Mask) throws -> Mask {
        switch seam.orientation {
        case .vertical:
            return try removeVertical(seam, from: mask)
        case .horizontal:
            let transposedMask = try transpose(mask)
            let verticalSeam = try SeamPath(orientation: .vertical, coordinates: seam.coordinates, totalCost: seam.totalCost)
            let result = try removeVertical(verticalSeam, from: transposedMask)
            return try transpose(result)
        }
    }

    public static func transpose(_ image: RGBA8Image) throws -> RGBA8Image {
        let newWidth = image.height
        let newHeight = image.width
        var pixels = [UInt8](repeating: 0, count: image.pixels.count)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let srcBase = (y * image.width + x) * 4
                let dstBase = (x * newWidth + y) * 4
                pixels[dstBase] = image.pixels[srcBase]
                pixels[dstBase + 1] = image.pixels[srcBase + 1]
                pixels[dstBase + 2] = image.pixels[srcBase + 2]
                pixels[dstBase + 3] = image.pixels[srcBase + 3]
            }
        }
        return try RGBA8Image(width: newWidth, height: newHeight, pixels: pixels)
    }

    public static func transpose(_ mask: Mask) throws -> Mask {
        let newWidth = mask.height
        let newHeight = mask.width
        var values = [Float](repeating: 0, count: mask.values.count)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                values[x * newWidth + y] = mask.values[y * mask.width + x]
            }
        }
        return try Mask(width: newWidth, height: newHeight, values: values)
    }

    // MARK: - Vertical removal

    private static func removeVertical(_ seam: SeamPath, from image: RGBA8Image) throws -> RGBA8Image {
        let width = image.width
        let height = image.height
        let coordinates = try validatedVerticalSeam(seam, length: height, upperBound: width)

        let newWidth = width - 1
        var pixels = [UInt8]()
        pixels.reserveCapacity(newWidth * height * 4)
        for y in 0..<height {
            let rowStart = y * width * 4
            let removeStart = coordinates[y] * 4
            pixels.append(contentsOf: image.pixels[rowStart..<(rowStart + removeStart)])
            pixels.append(contentsOf: image.pixels[(rowStart + removeStart + 4)..<(rowStart + width * 4)])
        }
        return try RGBA8Image(width: newWidth, height: height, pixels: pixels)
    }

    private static func removeVertical(_ seam: SeamPath, from mask: Mask) throws -> Mask {
        let width = mask.width
        let height = mask.height
        let coordinates = try validatedVerticalSeam(seam, length: height, upperBound: width)

        let newWidth = width - 1
        var values = [Float]()
        values.reserveCapacity(newWidth * height)
        for y in 0..<height {
            let rowStart = y * width
            let removeAt = coordinates[y]
            values.append(contentsOf: mask.values[rowStart..<(rowStart + removeAt)])
            values.append(contentsOf: mask.values[(rowStart + removeAt + 1)..<(rowStart + width)])
        }
        return try Mask(width: newWidth, height: height, values: values)
    }

    /// Validates a vertical seam: exact length, in-range coordinates, and
    /// unit-step continuity between adjacent rows. Returns Int coordinates.
    private static func validatedVerticalSeam(_ seam: SeamPath, length: Int, upperBound: Int) throws -> [Int] {
        guard seam.coordinates.count == length else {
            throw SeamCarvingError.invalidSeam
        }
        var result = [Int]()
        result.reserveCapacity(length)
        var previous: Int?
        for raw in seam.coordinates {
            let coordinate = Int(raw)
            guard coordinate >= 0, coordinate < upperBound else {
                throw SeamCarvingError.invalidSeam
            }
            if let previous, abs(coordinate - previous) > 1 {
                throw SeamCarvingError.invalidSeam
            }
            result.append(coordinate)
            previous = coordinate
        }
        return result
    }

    // MARK: - Insertion

    /// Inserts mapped vertical seams into an image in a single gather pass. Each
    /// seam holds original-row x-coordinates; inserted pixels average the left and
    /// right neighbors in linear light (alpha uses a rounded arithmetic mean), and
    /// duplicate the edge pixel when no right neighbor exists.
    public static func insertMappedVerticalSeams(
        _ seams: [[UInt32]],
        into image: RGBA8Image,
        policy: InsertionPolicy
    ) throws -> RGBA8Image {
        let width = image.width
        let height = image.height
        let count = seams.count
        for seam in seams {
            guard seam.count == height else {
                throw SeamCarvingError.invalidSeam
            }
            for raw in seam {
                guard Int(raw) >= 0, Int(raw) < width else {
                    throw SeamCarvingError.invalidSeam
                }
            }
        }

        let newWidth = width + count
        var pixels = [UInt8]()
        pixels.reserveCapacity(newWidth * height * 4)

        for y in 0..<height {
            let positions = seams.map { Int($0[y]) }.sorted()
            var nextInsert = 0
            for x in 0..<width {
                let base = (y * width + x) * 4
                pixels.append(contentsOf: image.pixels[base..<(base + 4)])
                while nextInsert < positions.count, positions[nextInsert] == x {
                    let pixel = neighborAverage(image, x: x, y: y, policy: policy)
                    pixels.append(pixel.r)
                    pixels.append(pixel.g)
                    pixels.append(pixel.b)
                    pixels.append(pixel.a)
                    nextInsert += 1
                }
            }
        }
        return try RGBA8Image(width: newWidth, height: height, pixels: pixels)
    }

    /// Inserts mapped vertical seams into a mask, mirroring the image edit.
    public static func insertMappedVerticalSeams(
        _ seams: [[UInt32]],
        into mask: Mask
    ) throws -> Mask {
        let width = mask.width
        let height = mask.height
        let count = seams.count
        for seam in seams {
            guard seam.count == height else {
                throw SeamCarvingError.invalidSeam
            }
            for raw in seam {
                guard Int(raw) >= 0, Int(raw) < width else {
                    throw SeamCarvingError.invalidSeam
                }
            }
        }

        let newWidth = width + count
        var values = [Float]()
        values.reserveCapacity(newWidth * height)

        for y in 0..<height {
            let positions = seams.map { Int($0[y]) }.sorted()
            var nextInsert = 0
            for x in 0..<width {
                values.append(mask.values[y * width + x])
                while nextInsert < positions.count, positions[nextInsert] == x {
                    let rightX = min(x + 1, width - 1)
                    values.append((mask.values[y * width + x] + mask.values[y * width + rightX]) / 2)
                    nextInsert += 1
                }
            }
        }
        return try Mask(width: newWidth, height: height, values: values)
    }

    private static func neighborAverage(_ image: RGBA8Image, x: Int, y: Int, policy: InsertionPolicy) -> RGBA8 {
        switch policy {
        case .neighborAverage:
            let rightX = min(x + 1, image.width - 1)
            let left = image[x, y]
            let right = image[rightX, y]
            let r = LinearSRGB.encode((LinearSRGB.table[Int(left.r)] + LinearSRGB.table[Int(right.r)]) / 2)
            let g = LinearSRGB.encode((LinearSRGB.table[Int(left.g)] + LinearSRGB.table[Int(right.g)]) / 2)
            let b = LinearSRGB.encode((LinearSRGB.table[Int(left.b)] + LinearSRGB.table[Int(right.b)]) / 2)
            let a = UInt8((UInt16(left.a) + UInt16(right.a) + 1) / 2)
            return RGBA8(r: r, g: g, b: b, a: a)
        }
    }
}

public enum InsertionPolicy: Sendable, Equatable {
    case neighborAverage
}
