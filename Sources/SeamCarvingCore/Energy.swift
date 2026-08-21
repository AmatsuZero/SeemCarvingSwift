import Foundation

public enum EnergyMode: Sendable, Equatable {
    case backwardSobel
    case forwardLuma
}

/// A row-major Float32 map of per-pixel energy.
public struct EnergyMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) throws {
        guard width > 0, height > 0 else {
            throw SeamCarvingError.invalidDimensions
        }
        let expected = try checkedMultiply(width, height)
        guard values.count == expected else {
            throw SeamCarvingError.invalidConfiguration("energy values count mismatch")
        }
        for value in values where value.isNaN || value == -.infinity {
            throw SeamCarvingError.invalidConfiguration("energy values must not be NaN or negative infinity")
        }
        self.width = width
        self.height = height
        self.values = values
    }

    public subscript(_ x: Int, _ y: Int) -> Float {
        values[y * width + x]
    }
}

extension EnergyMap {
    /// Adds a per-pixel adjustment (e.g., a mask adjustment) to this energy map.
    func adding(_ adjustment: EnergyMap) throws -> EnergyMap {
        guard adjustment.width == width, adjustment.height == height else {
            throw SeamCarvingError.invalidConfiguration("energy adjustment dimensions mismatch")
        }
        var values = self.values
        for i in 0..<values.count {
            values[i] += adjustment.values[i]
        }
        return try EnergyMap(width: width, height: height, values: values)
    }
}

/// The IEC 61966-2-1 sRGB transfer function, precomputed as a 256-entry lookup table.
internal enum LinearSRGB {
    static let table: [Float] = (0...255).map { byte -> Float in
        let c = Float(byte) / 255
        if c <= 0.04045 {
            return c / 12.92
        }
        return pow((c + 0.055) / 1.055, 2.4)
    }
}

/// Linear-light luma using the BT.709 coefficients, applied after sRGB decoding.
@inline(__always)
internal func linearLuma(r: UInt8, g: UInt8, b: UInt8) -> Float {
    let lr = LinearSRGB.table[Int(r)]
    let lg = LinearSRGB.table[Int(g)]
    let lb = LinearSRGB.table[Int(b)]
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
}
