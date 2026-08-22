import CoreGraphics
import Foundation
import SeamCarvingCore
#if canImport(CoreImage)
import CoreImage
#endif

/// Pre-scale planning that runs in the Apple layer (where Core Image is
/// available). Core Image / Core Graphics must never be imported by
/// `SeamCarvingCore`, so this boundary lives here: it hands the backend a
/// canonical RGBA8 image and masks AFTER planning.
enum PreScalePlanner {
    struct Planned {
        let image: RGBA8Image
        let masks: MaskPair
    }

    /// Computes the intermediate size "most of the way" from `source` to
    /// `target`. The residual seam carving always reaches the exact `target`,
    /// so this only needs to be valid (>= 1 in each axis) and deterministic.
    static func intermediateSize(source: PixelSize, target: PixelSize) -> PixelSize {
        // Halfway between source and target; for a no-op source == target this
        // collapses to target and the residual carving is itself a no-op.
        let w = max(1, Int((Double(source.width) * 0.5 + Double(target.width) * 0.5).rounded()))
        let h = max(1, Int((Double(source.height) * 0.5 + Double(target.height) * 0.5).rounded()))
        return try! PixelSize(width: w, height: h)
    }

    static func plan(
        image: RGBA8Image,
        masks: MaskPair,
        target: PixelSize,
        strategy: PreScaleStrategy
    ) throws -> Planned {
        switch strategy {
        case .none:
            return Planned(image: image, masks: masks)
        case .lanczosThenExactResidual:
            #if canImport(CoreImage)
            let source = try PixelSize(width: image.width, height: image.height)
            guard source != target else {
                return Planned(image: image, masks: masks)
            }
            let intermediate = intermediateSize(source: source, target: target)
            let scaledImage = try lanczosScale(image, to: intermediate)
            let scaledMasks = try lanczosScaleMasks(masks, to: intermediate)
            return Planned(image: scaledImage, masks: scaledMasks)
            #else
            throw SeamCarvingError.invalidConfiguration(
                "preScaleStrategy .lanczosThenExactResidual requires Core Image, which is unavailable on this platform"
            )
            #endif
        }
    }

    #if canImport(CoreImage)
    /// Lanczos-scales an RGBA8 image to the exact target size via Core Image.
    private static func lanczosScale(_ image: RGBA8Image, to size: PixelSize) throws -> RGBA8Image {
        let cgImage = try CGImageBridge.encode(image)
        let ciImage = CIImage(cgImage: cgImage)
        let scaled = try lanczosScaleCIImage(ciImage, from: (ciImage.extent.width, ciImage.extent.height), to: size)
        let context = CIContext()
        guard let outCG = context.createCGImage(scaled, from: scaled.extent) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        return try CGImageBridge.decode(outCG)
    }

    /// Lanczos-scales a single mask (Float values in 0...1) to the target size.
    private static func lanczosScaleMasks(_ masks: MaskPair, to size: PixelSize) throws -> MaskPair {
        var scaledLayers: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let scaledMask = try lanczosScaleMask(layer.mask, to: size)
            scaledLayers.append(try ProtectionLayer(mask: scaledMask, strength: layer.strength))
        }
        var scaledRemoval: Mask?
        if let removal = masks.removal {
            scaledRemoval = try lanczosScaleMask(removal, to: size)
        }
        return try MaskPair(
            protectionLayers: scaledLayers,
            removal: scaledRemoval,
            removalWeight: masks.removalWeight
        )
    }

    private static func lanczosScaleMask(_ mask: Mask, to size: PixelSize) throws -> Mask {
        let ciImage = try maskToCIImage(mask)
        let scaled = try lanczosScaleCIImage(ciImage, from: (Double(mask.width), Double(mask.height)), to: size)
        let context = CIContext()
        guard let outCG = context.createCGImage(scaled, from: scaled.extent) else {
            throw SeamCarvingError.unsupportedPixelFormat
        }
        let decoded = try CGImageBridge.decode(outCG)
        // Core Image may return a buffer slightly different in size from the
        // requested crop. Sample from the decoded buffer's actual grid, mapping
        // each target pixel to the nearest decoded pixel.
        let srcW = decoded.width
        let srcH = decoded.height
        var values = [Float](repeating: 0, count: size.width * size.height)
        for y in 0..<size.height {
            let sy = min(srcH - 1, Int((Double(y) * Double(srcH) / Double(size.height)).rounded()))
            for x in 0..<size.width {
                let sx = min(srcW - 1, Int((Double(x) * Double(srcW) / Double(size.width)).rounded()))
                let px = decoded[sx, sy]
                // Mask was encoded as grayscale straight alpha; recover 0...1.
                values[y * size.width + x] = Float(px.r) / 255.0
            }
        }
        return try Mask(width: size.width, height: size.height, values: values)
    }

    /// Maps a CIImage of size `from` to exactly `to` using Lanczos.
    private static func lanczosScaleCIImage(
        _ image: CIImage,
        from: (CGFloat, CGFloat),
        to size: PixelSize
    ) throws -> CIImage {
        let targetW = CGFloat(size.width)
        let targetH = CGFloat(size.height)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw SeamCarvingError.invalidConfiguration("CILanczosScaleTransform is unavailable")
        }
        // Use the larger axis scale so the output is guaranteed to cover the
        // target; the crop then clamps to the exact integer target extent.
        let scale = max(targetW / from.0, targetH / from.1)
        let aspectRatio = (targetH / from.1) / (targetW / from.0)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: "inputScale")
        filter.setValue(aspectRatio, forKey: "inputAspectRatio")
        guard let output = filter.outputImage else {
            throw SeamCarvingError.invalidConfiguration("Lanczos pre-scale produced no output")
        }
        // Crop to the exact integer target extent.
        return output.cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))
    }

    /// Encodes a mask (0...1) into a grayscale, opaque CIImage.
    private static func maskToCIImage(_ mask: Mask) throws -> CIImage {
        var pixels = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for i in 0..<(mask.width * mask.height) {
            let v = UInt8(min(max(mask.values[i], 0), 1) * 255)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 255
        }
        let rgba = try RGBA8Image(width: mask.width, height: mask.height, pixels: pixels)
        return CIImage(cgImage: try CGImageBridge.encode(rgba))
    }
    #endif
}
