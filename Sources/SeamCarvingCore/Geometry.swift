/// Multiplies two dimensions with overflow checking so malicious sizes cannot wrap.
@inlinable
internal func checkedMultiply(_ a: Int, _ b: Int) throws -> Int {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    guard !overflow else { throw SeamCarvingError.invalidDimensions }
    return result
}

public struct PixelSize: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw SeamCarvingError.invalidDimensions
        }
        self.width = width
        self.height = height
    }
}

public extension PixelSize {
    /// Resolves a percentage scale of the source to a concrete target size.
    ///
    /// `percentage` is relative to the source dimensions (`50` means half), each
    /// axis is rounded half away from zero, and every axis is clamped to at least
    /// `1`. Values above `100` enlarge the image; values below `100` shrink it.
    func scaled(byPercentage percentage: Float) throws -> PixelSize {
        guard percentage.isFinite, percentage > 0 else {
            throw SeamCarvingError.invalidConfiguration("percentage must be finite and positive")
        }
        let scaledWidth = (Double(self.width) * Double(percentage) / 100.0).rounded()
        let scaledHeight = (Double(self.height) * Double(percentage) / 100.0).rounded()
        guard let widthExact = Int(exactly: scaledWidth),
              let heightExact = Int(exactly: scaledHeight) else {
            throw SeamCarvingError.invalidConfiguration("percentage produces an out-of-range target size")
        }
        let width = max(1, widthExact)
        let height = max(1, heightExact)
        return try PixelSize(width: width, height: height)
    }

    /// Resolves a square target whose side equals the source's shorter side.
    ///
    /// The longer dimension is carved down to the shorter one, so the target
    /// never exceeds either source dimension (no enlargement is required).
    func squareTarget() -> PixelSize {
        let side = min(width, height)
        // `side` is the minimum of two already-validated positive dimensions.
        return try! PixelSize(width: side, height: side)
    }
}

public enum SeamOrientation: Sendable, Equatable {
    case vertical
    case horizontal
}

public struct SeamPath: Sendable, Equatable {
    public let orientation: SeamOrientation
    public let coordinates: [UInt32]
    public let totalCost: Float

    public init(orientation: SeamOrientation, coordinates: [UInt32], totalCost: Float) throws {
        guard totalCost.isFinite else {
            throw SeamCarvingError.invalidSeam
        }
        self.orientation = orientation
        self.coordinates = coordinates
        self.totalCost = totalCost
    }
}
