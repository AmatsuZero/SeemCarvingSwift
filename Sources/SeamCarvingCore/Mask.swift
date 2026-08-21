public struct Mask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) throws {
        guard width > 0, height > 0 else {
            throw SeamCarvingError.invalidDimensions
        }
        let expected = try checkedMultiply(width, height)
        guard values.count == expected else {
            throw SeamCarvingError.invalidMaskCount(expected: expected, actual: values.count)
        }
        for value in values where !value.isFinite || value < 0 || value > 1 {
            throw SeamCarvingError.invalidConfiguration("mask values must be finite and within 0...1")
        }
        self.width = width
        self.height = height
        self.values = values
    }

    public subscript(_ x: Int, _ y: Int) -> Float {
        get { values[y * width + x] }
        set { values[y * width + x] = newValue }
    }
}
