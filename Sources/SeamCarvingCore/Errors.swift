public enum SeamCarvingError: Error, Equatable {
    case invalidDimensions
    case invalidPixelCount(expected: Int, actual: Int)
    case invalidMaskCount(expected: Int, actual: Int)
    case invalidTarget(source: PixelSize, target: PixelSize)
    case invalidSeam
    case noFeasibleSeam
    case invalidConfiguration(String)
    case metalUnavailable
    case metalExecutionFailed(String)
    case unsupportedPixelFormat
    case unsupportedDynamicRange
}
