public struct RGBA8: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public struct RGBA8Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw SeamCarvingError.invalidDimensions
        }
        let pixelCount = try checkedMultiply(width, height)
        let expected = try checkedMultiply(pixelCount, 4)
        guard pixels.count == expected else {
            throw SeamCarvingError.invalidPixelCount(expected: expected, actual: pixels.count)
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public static func solid(width: Int, height: Int, color: RGBA8) throws -> RGBA8Image {
        let total = try checkedMultiply(try checkedMultiply(width, height), 4)
        var pixels = [UInt8](repeating: 0, count: total)
        for index in stride(from: 0, to: total, by: 4) {
            pixels[index] = color.r
            pixels[index + 1] = color.g
            pixels[index + 2] = color.b
            pixels[index + 3] = color.a
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    public subscript(_ x: Int, _ y: Int) -> RGBA8 {
        get {
            let base = (y * width + x) * 4
            return RGBA8(
                r: pixels[base],
                g: pixels[base + 1],
                b: pixels[base + 2],
                a: pixels[base + 3]
            )
        }
        set {
            let base = (y * width + x) * 4
            pixels[base] = newValue.r
            pixels[base + 1] = newValue.g
            pixels[base + 2] = newValue.b
            pixels[base + 3] = newValue.a
        }
    }
}
