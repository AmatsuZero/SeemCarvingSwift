@_spi(Backend)
public protocol SeamCarvingBackend: Sendable {
    var identifier: String { get }
    func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath
    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image
}

@_spi(Backend)
public protocol BackwardEnergyProvider: Sendable {
    func compute(for image: RGBA8Image) throws -> EnergyMap
}

/// Shared orchestration for exact sequential seam carving. CPU and Accelerate
/// backends both reuse this engine and only replace energy computation.
@_spi(Backend)
public struct CoreResizeEngine: Sendable {
    private let backwardEnergyProvider: any BackwardEnergyProvider

    public init(backwardEnergyProvider: any BackwardEnergyProvider) {
        self.backwardEnergyProvider = backwardEnergyProvider
    }

    public func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions
    ) async throws -> SeamPath {
        try findSeam(in: image, orientation: orientation, energyMode: options.energyMode, masks: options.masks)
    }

    private func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        energyMode: EnergyMode,
        masks: MaskPair
    ) throws -> SeamPath {
        switch energyMode {
        case .backwardSobel:
            let base = try backwardEnergyProvider.compute(for: image)
            if let adjustment = try masks.energyAdjustment(forWidth: image.width, height: image.height) {
                return try DynamicProgramming.findSeam(in: try base.adding(adjustment), orientation: orientation)
            }
            return try DynamicProgramming.findSeam(in: base, orientation: orientation)
        case .forwardLuma:
            let luminance = try LuminancePlane.luma(of: image)
            let adjustment = try masks.energyAdjustment(forWidth: image.width, height: image.height)
            return try ForwardEnergy.findSeam(in: luminance, orientation: orientation, adjustedBaseEnergy: adjustment)
        }
    }

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image {
        guard target.width <= image.width, target.height <= image.height else {
            throw SeamCarvingError.invalidTarget(
                source: try PixelSize(width: image.width, height: image.height),
                target: target
            )
        }
        try options.masks.validateDimensions(width: image.width, height: image.height)

        var current = image
        var currentMasks = options.masks
        var remainingVertical = image.width - target.width
        var remainingHorizontal = image.height - target.height
        let totalEdits = remainingVertical + remainingHorizontal
        var completedEdits = 0

        while remainingVertical > 0 || remainingHorizontal > 0 {
            try Task.checkCancellation()

            let seam: SeamPath
            let orientation: SeamOrientation
            switch options.dimensionOrder {
            case .widthThenHeight:
                orientation = remainingVertical > 0 ? .vertical : .horizontal
                seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks)
            case .heightThenWidth:
                orientation = remainingHorizontal > 0 ? .horizontal : .vertical
                seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks)
            case .adaptiveNormalizedCost:
                if remainingVertical == 0 {
                    orientation = .horizontal
                    seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks)
                } else if remainingHorizontal == 0 {
                    orientation = .vertical
                    seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks)
                } else {
                    let verticalSeam = try findSeam(in: current, orientation: .vertical, energyMode: options.energyMode, masks: currentMasks)
                    let horizontalSeam = try findSeam(in: current, orientation: .horizontal, energyMode: options.energyMode, masks: currentMasks)
                    let verticalNormalized = verticalSeam.totalCost / Float(current.height)
                    let horizontalNormalized = horizontalSeam.totalCost / Float(current.width)
                    if verticalNormalized <= horizontalNormalized {
                        orientation = .vertical
                        seam = verticalSeam
                    } else {
                        orientation = .horizontal
                        seam = horizontalSeam
                    }
                }
            }

            current = try SeamEditor.remove(seam, from: current)
            currentMasks = try removing(seam, from: currentMasks)

            if orientation == .vertical {
                remainingVertical -= 1
            } else {
                remainingHorizontal -= 1
            }
            completedEdits += 1
            options.progress?(ResizeProgress(
                completedEdits: completedEdits,
                totalEdits: totalEdits,
                size: try PixelSize(width: current.width, height: current.height)
            ))
        }

        return current
    }

    /// Removes a seam from every layer of a mask pair, preserving each layer's
    /// independent soft/hard strength.
    private func removing(_ seam: SeamPath, from masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try SeamEditor.remove(seam, from: layer.mask)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.remove(seam, from: removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }
}
