import CoreGraphics
@_exported import SeamCarvingAppleRuntime
import SeamCarvingCore

public extension AppleSeamCarver {
    func resize(
        _ image: CGImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage {
        let decoded = try CGImageBridge.decode(image)
        let planned = try PreScalePlanner.plan(
            image: decoded,
            masks: options.masks,
            target: target,
            strategy: options.preScaleStrategy
        )
        var plannedOptions = options
        plannedOptions.masks = planned.masks
        let result = try await resize(planned.image, toPixelSize: target, options: plannedOptions)
        return try CGImageBridge.encode(result)
    }

    func findSeam(
        in image: CGImage,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath {
        let decoded = try CGImageBridge.decode(image)
        return try await findSeam(in: decoded, orientation: orientation, options: options)
    }
}
