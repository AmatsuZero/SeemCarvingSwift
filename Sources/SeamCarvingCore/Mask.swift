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

extension MaskPair {
    /// Validates that every protection and removal mask matches the given size.
    @_spi(Backend)
    public func validateDimensions(width: Int, height: Int) throws {
        for layer in protectionLayers {
            guard layer.mask.width == width, layer.mask.height == height else {
                throw SeamCarvingError.invalidConfiguration("protection mask dimensions must match image")
            }
        }
        if let removal {
            guard removal.width == width, removal.height == height else {
                throw SeamCarvingError.invalidConfiguration("removal mask dimensions must match image")
            }
        }
    }

    /// Computes the per-pixel energy adjustment from independent protection and
    /// removal layers, or nil when no layer is present. Hard protection yields
    /// `+infinity` and overrides removal. Each layer is applied independently.
    @_spi(Backend)
    public func energyAdjustment(forWidth width: Int, height: Int) throws -> EnergyMap? {
        guard !protectionLayers.isEmpty || removal != nil else { return nil }
        try validateDimensions(width: width, height: height)

        let pixelCount = width * height
        var values = [Float](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            var v: Float = 0
            var hardProtected = false
            for layer in protectionLayers {
                switch layer.strength {
                case .soft(let weight):
                    v += weight * layer.mask.values[i]
                case .hard:
                    if layer.mask.values[i] > 0 {
                        hardProtected = true
                    }
                }
            }
            if hardProtected {
                values[i] = .infinity
            } else {
                if let removal {
                    v -= removalWeight * removal.values[i]
                }
                values[i] = v
            }
        }
        return try EnergyMap(width: width, height: height, values: values)
    }
}
