import CoreGraphics
import ImageIO
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
import SeamCarvingApple

public struct FaceAwareSeamCarver: Sendable {
    private let appleCarver: AppleSeamCarver
    private let detector: any FaceDetecting
    private let policy: FaceProtectionPolicy
    private let cadence: FaceDetectionCadence

    public init(
        configuration: AppleSeamCarverConfiguration = .init(),
        detector: any FaceDetecting,
        policy: FaceProtectionPolicy,
        cadence: FaceDetectionCadence = .detectOnceAndTransformMask
    ) throws {
        self.appleCarver = try AppleSeamCarver(configuration: configuration)
        self.detector = detector
        self.policy = policy
        self.cadence = cadence
    }

    public func resize(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage {
        try options.masks.validateDimensions(width: image.width, height: image.height)

        // Orient user masks into upright coordinates.
        let orientedUserMasks = try Self.orientMasks(options.masks, orientation: orientation)

        // Decode to an upright canonical image.
        let upright = try CGImageBridge.decode(image, orientation: orientation)
        let uprightCG = try CGImageBridge.encode(upright)

        switch cadence {
        case .detectOnceAndTransformMask:
            let regions = try await detector.detectFaces(inUpright: uprightCG)
            let faceMask = try FaceMaskRasterizer.rasterize(
                regions: regions,
                size: try PixelSize(width: upright.width, height: upright.height),
                policy: policy
            )
            var effective = options
            effective.masks = try EnergyComposer.compose(userMasks: orientedUserMasks, faceMask: faceMask, policy: policy)
            return try await appleCarver.resize(uprightCG, toPixelSize: target, options: effective)

        case .redetectEveryPass:
            return try await redetectResize(from: upright, userMasks: orientedUserMasks, to: target, options: options)
        }
    }

    private func redetectResize(
        from image: RGBA8Image,
        userMasks: MaskPair,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> CGImage {
        var currentImage = image
        var currentUserMasks = userMasks
        var remainingVertical = image.width - target.width
        var remainingHorizontal = image.height - target.height

        guard remainingVertical >= 0, remainingHorizontal >= 0 else {
            throw SeamCarvingError.invalidConfiguration(
                "redetectEveryPass currently supports seam removal only; use detectOnceAndTransformMask for enlargement"
            )
        }

        while remainingVertical > 0 || remainingHorizontal > 0 {
            try Task.checkCancellation()

            let currentCG = try CGImageBridge.encode(currentImage)
            let regions = try await detector.detectFaces(inUpright: currentCG)
            let faceMask = try FaceMaskRasterizer.rasterize(
                regions: regions,
                size: try PixelSize(width: currentImage.width, height: currentImage.height),
                policy: policy
            )
            let effective = try EnergyComposer.compose(userMasks: currentUserMasks, faceMask: faceMask, policy: policy)

            var effectiveOptions = options
            effectiveOptions.masks = effective
            let orientation: SeamOrientation
            switch options.dimensionOrder {
            case .widthThenHeight:
                orientation = remainingVertical > 0 ? .vertical : .horizontal
            case .heightThenWidth:
                orientation = remainingHorizontal > 0 ? .horizontal : .vertical
            case .adaptiveNormalizedCost:
                if remainingVertical == 0 {
                    orientation = .horizontal
                } else if remainingHorizontal == 0 {
                    orientation = .vertical
                } else {
                    let vertical = try await appleCarver.findSeam(
                        in: currentCG, orientation: .vertical, options: effectiveOptions
                    )
                    let horizontal = try await appleCarver.findSeam(
                        in: currentCG, orientation: .horizontal, options: effectiveOptions
                    )
                    let verticalNormalized = vertical.totalCost / Float(currentImage.height)
                    let horizontalNormalized = horizontal.totalCost / Float(currentImage.width)
                    orientation = verticalNormalized <= horizontalNormalized ? .vertical : .horizontal
                }
            }
            let seam = try await appleCarver.findSeam(in: currentCG, orientation: orientation, options: effectiveOptions)

            currentImage = try SeamEditor.remove(seam, from: currentImage)
            currentUserMasks = try Self.removingSeam(seam, from: currentUserMasks)

            if orientation == .vertical {
                remainingVertical -= 1
            } else {
                remainingHorizontal -= 1
            }
        }

        return try CGImageBridge.encode(currentImage)
    }

    // MARK: - Helpers

    private static func orientMasks(_ masks: MaskPair, orientation: CGImagePropertyOrientation) throws -> MaskPair {
        var protection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let oriented = try CGImageBridge.applyOrientation(orientation, to: layer.mask)
            protection.append(try ProtectionLayer(mask: oriented, strength: layer.strength))
        }
        let removal: Mask?
        if let r = masks.removal {
            removal = try CGImageBridge.applyOrientation(orientation, to: r)
        } else {
            removal = nil
        }
        return try MaskPair(protectionLayers: protection, removal: removal, removalWeight: masks.removalWeight)
    }

    private static func removingSeam(_ seam: SeamPath, from masks: MaskPair) throws -> MaskPair {
        var protection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try SeamEditor.remove(seam, from: layer.mask)
            protection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let removal: Mask?
        if let r = masks.removal {
            removal = try SeamEditor.remove(seam, from: r)
        } else {
            removal = nil
        }
        return try MaskPair(protectionLayers: protection, removal: removal, removalWeight: masks.removalWeight)
    }
}
