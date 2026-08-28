import SeamCarvingCore

public struct AndroidResizeResult {
    public let width: Int32
    public let height: Int32
    public let bytes: [UInt8]

    public init(width: Int32, height: Int32, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}

public enum AndroidResizeBridge {
    public static func resize(
        width: Int32,
        height: Int32,
        bytes: [UInt8],
        targetWidth: Int32,
        targetHeight: Int32,
        protectionMask: [Float],
        removalMask: [Float]
    ) async throws -> AndroidResizeResult {
        let source = try RGBA8Image(
            width: Int(width),
            height: Int(height),
            pixels: bytes
        )
        let target = try PixelSize(width: Int(targetWidth), height: Int(targetHeight))
        let masks = try MaskPair(
            protectionLayers: protectionMask.isEmpty ? [] : [
                try ProtectionLayer(
                    mask: Mask(width: source.width, height: source.height, values: protectionMask),
                    strength: .soft(1_000)
                ),
            ],
            removal: removalMask.isEmpty
                ? nil
                : try Mask(width: source.width, height: source.height, values: removalMask),
            removalWeight: 1_000
        )
        let result = try await SeamCarver().resize(
            source,
            to: target,
            options: ResizeOptions(masks: masks)
        )
        return AndroidResizeResult(
            width: try checkedDimension(result.width),
            height: try checkedDimension(result.height),
            bytes: result.pixels
        )
    }

    private static func checkedDimension(_ value: Int) throws -> Int32 {
        guard let dimension = Int32(exactly: value) else {
            throw SeamCarvingError.invalidDimensions
        }
        return dimension
    }
}
