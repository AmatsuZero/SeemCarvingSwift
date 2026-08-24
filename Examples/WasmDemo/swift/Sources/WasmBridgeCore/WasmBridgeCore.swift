import SeamCarvingCore

/// A tightly packed, row-major RGBA8 image resize request.
///
/// Pixels use straight alpha in sRGB byte order: red, green, blue, alpha.
public struct ResizeRGBA8Request: Sendable, Equatable {
    public let pixels: [UInt8]
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let targetWidth: Int
    public let targetHeight: Int

    public init(
        pixels: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) {
        self.pixels = pixels
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
    }
}

/// The resized RGBA8 buffer returned by ``resizeRGBA8(_:)``.
public struct ResizeRGBA8Response: Sendable, Equatable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int

    public init(pixels: [UInt8], width: Int, height: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
    }
}

/// Validation errors at the browser/Swift bridge boundary.
///
/// These cases deliberately avoid UI strings: JavaScript maps them to the
/// appropriate localized, user-facing message.
public enum WasmBridgeError: Error, Equatable, Sendable {
    case invalidDimensions
    case dimensionOverflow
    case invalidByteCount(expected: Int, actual: Int)
    case sourcePixelLimitExceeded(limit: Int)
    case targetPixelLimitExceeded(limit: Int)
    case estimatedWorkLimitExceeded(limit: Int)
}

private let pixelLimit = 2_000_000
private let estimatedWorkLimit = 80_000_000

/// Resizes a compact RGBA8 buffer with the CPU seam-carving implementation.
///
/// The bridge bounds source pixels, target pixels, and estimated seam work
/// before allocating an image or invoking Core.
public func resizeRGBA8(_ request: ResizeRGBA8Request) async throws -> ResizeRGBA8Response {
    try validate(request)

    let image = try RGBA8Image(
        width: request.sourceWidth,
        height: request.sourceHeight,
        pixels: request.pixels
    )
    let target = try PixelSize(width: request.targetWidth, height: request.targetHeight)
    let result = try await SeamCarver().resize(image, to: target)
    return ResizeRGBA8Response(pixels: result.pixels, width: result.width, height: result.height)
}

private func validate(_ request: ResizeRGBA8Request) throws {
    guard request.sourceWidth > 0,
          request.sourceHeight > 0,
          request.targetWidth > 0,
          request.targetHeight > 0 else {
        throw WasmBridgeError.invalidDimensions
    }

    let sourcePixels = try checkedProduct(request.sourceWidth, request.sourceHeight)
    let targetPixels = try checkedProduct(request.targetWidth, request.targetHeight)

    guard sourcePixels <= pixelLimit else {
        throw WasmBridgeError.sourcePixelLimitExceeded(limit: pixelLimit)
    }
    guard targetPixels <= pixelLimit else {
        throw WasmBridgeError.targetPixelLimitExceeded(limit: pixelLimit)
    }

    // Positive validated dimensions make these subtractions and absolute
    // values safe: their difference is strictly greater than Int.min.
    let widthEdits = request.sourceWidth >= request.targetWidth
        ? request.sourceWidth - request.targetWidth
        : request.targetWidth - request.sourceWidth
    let heightEdits = request.sourceHeight >= request.targetHeight
        ? request.sourceHeight - request.targetHeight
        : request.targetHeight - request.sourceHeight
    let widthWork = try checkedProduct(widthEdits, request.sourceHeight)
    let heightWork = try checkedProduct(heightEdits, request.targetWidth)
    let (estimatedWork, workOverflow) = widthWork.addingReportingOverflow(heightWork)
    guard !workOverflow else { throw WasmBridgeError.dimensionOverflow }
    guard estimatedWork <= estimatedWorkLimit else {
        throw WasmBridgeError.estimatedWorkLimitExceeded(limit: estimatedWorkLimit)
    }

    let expectedByteCount = try checkedProduct(sourcePixels, 4)
    guard request.pixels.count == expectedByteCount else {
        throw WasmBridgeError.invalidByteCount(expected: expectedByteCount, actual: request.pixels.count)
    }
}

private func checkedProduct(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    guard !overflow else { throw WasmBridgeError.dimensionOverflow }
    return result
}
