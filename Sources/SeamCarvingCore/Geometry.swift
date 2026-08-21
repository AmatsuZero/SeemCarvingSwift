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
