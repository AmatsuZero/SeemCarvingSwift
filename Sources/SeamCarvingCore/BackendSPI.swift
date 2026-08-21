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

@_spi(Backend)
public struct MappedSeamSet: Sendable, Equatable {
    public let orientation: SeamOrientation
    public let coordinatesBySeam: [[UInt32]]

    public init(orientation: SeamOrientation, coordinatesBySeam: [[UInt32]]) throws {
        guard let first = coordinatesBySeam.first, !first.isEmpty else {
            throw SeamCarvingError.invalidConfiguration("empty mapped seam set")
        }
        for seam in coordinatesBySeam where seam.count != first.count {
            throw SeamCarvingError.invalidConfiguration("mapped seam length mismatch")
        }
        self.orientation = orientation
        self.coordinatesBySeam = coordinatesBySeam
    }
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
        try options.masks.validateDimensions(width: image.width, height: image.height)

        let widthDelta = target.width - image.width
        let heightDelta = target.height - image.height
        let totalEdits = abs(widthDelta) + abs(heightDelta)

        var current = image
        var currentMasks = options.masks
        var completed = 0

        switch options.dimensionOrder {
        case .widthThenHeight:
            (current, currentMasks, completed) = try await applyDimension(
                .vertical, delta: widthDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits
            )
            (current, currentMasks, completed) = try await applyDimension(
                .horizontal, delta: heightDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits
            )
        case .heightThenWidth:
            (current, currentMasks, completed) = try await applyDimension(
                .horizontal, delta: heightDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits
            )
            (current, currentMasks, completed) = try await applyDimension(
                .vertical, delta: widthDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits
            )
        case .adaptiveNormalizedCost:
            var remainingWidth = widthDelta
            var remainingHeight = heightDelta
            while remainingWidth != 0 || remainingHeight != 0 {
                try Task.checkCancellation()
                let orientation: SeamOrientation
                if remainingWidth == 0 {
                    orientation = .horizontal
                } else if remainingHeight == 0 {
                    orientation = .vertical
                } else {
                    let vertical = try findSeam(in: current, orientation: .vertical, energyMode: options.energyMode, masks: currentMasks)
                    let horizontal = try findSeam(in: current, orientation: .horizontal, energyMode: options.energyMode, masks: currentMasks)
                    let verticalNormalized = vertical.totalCost / Float(current.height)
                    let horizontalNormalized = horizontal.totalCost / Float(current.width)
                    orientation = verticalNormalized <= horizontalNormalized ? .vertical : .horizontal
                }
                let step = (orientation == .vertical ? remainingWidth : remainingHeight) > 0 ? 1 : -1
                (current, currentMasks, completed) = try await applyDimension(
                    orientation, delta: step, to: current, masks: currentMasks,
                    options: options, completed: completed, totalEdits: totalEdits
                )
                if orientation == .vertical {
                    remainingWidth -= step
                } else {
                    remainingHeight -= step
                }
            }
        }

        return current
    }

    // MARK: - Dimension application

    private func applyDimension(
        _ orientation: SeamOrientation,
        delta: Int,
        to image: RGBA8Image,
        masks: MaskPair,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        if delta < 0 {
            return try await shrinkDimension(image, masks: masks, count: -delta, orientation: orientation, options: options, completed: completed, totalEdits: totalEdits)
        }
        if delta > 0 {
            return try await enlargeDimension(image, masks: masks, count: delta, orientation: orientation, options: options, completed: completed, totalEdits: totalEdits)
        }
        return (image, masks, completed)
    }

    private func shrinkDimension(
        _ image: RGBA8Image,
        masks: MaskPair,
        count: Int,
        orientation: SeamOrientation,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        var current = image
        var currentMasks = masks
        var completed = completed
        for _ in 0..<count {
            try Task.checkCancellation()
            let seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks)
            current = try SeamEditor.remove(seam, from: current)
            currentMasks = try removing(seam, from: currentMasks)
            completed += 1
            options.progress?(ResizeProgress(completedEdits: completed, totalEdits: totalEdits, size: try PixelSize(width: current.width, height: current.height)))
        }
        return (current, currentMasks, completed)
    }

    private func enlargeDimension(
        _ image: RGBA8Image,
        masks: MaskPair,
        count: Int,
        orientation: SeamOrientation,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        var current = image
        var currentMasks = masks
        var completed = completed
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            let dimension = orientation == .vertical ? current.width : current.height
            let set: MappedSeamSet
            if dimension == 1 {
                let soleLength = orientation == .vertical ? current.height : current.width
                set = try MappedSeamSet(orientation: orientation, coordinatesBySeam: [[UInt32](repeating: 0, count: soleLength)])
            } else {
                let batchSize = min(remaining, dimension - 1)
                var opts = options
                opts.masks = currentMasks
                set = try await discoverMappedSeams(count: batchSize, in: current, orientation: orientation, options: opts)
            }

            let inserted = try insertMapped(set, into: current, masks: currentMasks)
            current = inserted.image
            currentMasks = inserted.masks
            remaining -= set.coordinatesBySeam.count
            completed += set.coordinatesBySeam.count
            options.progress?(ResizeProgress(completedEdits: completed, totalEdits: totalEdits, size: try PixelSize(width: current.width, height: current.height)))
        }
        return (current, currentMasks, completed)
    }

    // MARK: - Mapped seam discovery

    func discoverMappedVerticalSeams(count: Int, in image: RGBA8Image, options: ResizeOptions) async throws -> MappedSeamSet {
        let width = image.width
        let height = image.height
        guard count > 0, count < width else {
            throw SeamCarvingError.invalidConfiguration("seam count must be in 1..<width")
        }

        var working = image
        var workingMasks = options.masks
        var indexMap = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                indexMap[y * width + x] = UInt32(x)
            }
        }

        var seams: [[UInt32]] = []
        seams.reserveCapacity(count)
        for _ in 0..<count {
            try Task.checkCancellation()
            let currentWidth = working.width
            let seam = try findSeam(in: working, orientation: .vertical, energyMode: options.energyMode, masks: workingMasks)
            let mapped = seam.coordinates.enumerated().map { indexMap[$0.offset * currentWidth + Int($0.element)] }
            seams.append(mapped)
            working = try SeamEditor.remove(seam, from: working)
            workingMasks = try removing(seam, from: workingMasks)
            indexMap = try removeVerticalSeam(indexMap, seam: seam, width: currentWidth)
        }
        return try MappedSeamSet(orientation: .vertical, coordinatesBySeam: seams)
    }

    private func removeVerticalSeam(_ indexMap: [UInt32], seam: SeamPath, width: Int) throws -> [UInt32] {
        let height = seam.coordinates.count
        var result = [UInt32]()
        result.reserveCapacity((width - 1) * height)
        for y in 0..<height {
            let removeAt = Int(seam.coordinates[y])
            let rowStart = y * width
            result.append(contentsOf: indexMap[rowStart..<(rowStart + removeAt)])
            result.append(contentsOf: indexMap[(rowStart + removeAt + 1)..<(rowStart + width)])
        }
        return result
    }

    // MARK: - Insertion

    private func insertMapped(
        _ set: MappedSeamSet,
        into image: RGBA8Image,
        masks: MaskPair
    ) throws -> (image: RGBA8Image, masks: MaskPair) {
        switch set.orientation {
        case .vertical:
            let newImage = try SeamEditor.insertMappedVerticalSeams(set.coordinatesBySeam, into: image, policy: .neighborAverage)
            let newMasks = try inserting(set.coordinatesBySeam, into: masks)
            return (newImage, newMasks)
        case .horizontal:
            let transposedImage = try SeamEditor.transpose(image)
            let transposedMasks = try transposeMaskPair(masks)
            let insertedImage = try SeamEditor.insertMappedVerticalSeams(set.coordinatesBySeam, into: transposedImage, policy: .neighborAverage)
            let insertedMasks = try inserting(set.coordinatesBySeam, into: transposedMasks)
            return (try SeamEditor.transpose(insertedImage), try transposeMaskPair(insertedMasks))
        }
    }

    /// Inserts mapped vertical seams into every mask layer, preserving strength.
    private func inserting(_ seams: [[UInt32]], into masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try SeamEditor.insertMappedVerticalSeams(seams, into: layer.mask)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.insertMappedVerticalSeams(seams, into: removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }

    /// Removes a seam from every layer of a mask pair, preserving strength.
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

    func transposeMaskPair(_ masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            newProtection.append(try ProtectionLayer(mask: try SeamEditor.transpose(layer.mask), strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.transpose(removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }
}

@_spi(Backend)
public extension CoreResizeEngine {
    /// Discovers `count` seams mapped to original-image coordinates. Horizontal
    /// discovery transposes image and masks, runs vertical discovery, and re-labels.
    func discoverMappedSeams(
        count: Int,
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions
    ) async throws -> MappedSeamSet {
        try options.masks.validateDimensions(width: image.width, height: image.height)
        switch orientation {
        case .vertical:
            return try await discoverMappedVerticalSeams(count: count, in: image, options: options)
        case .horizontal:
            let transposedImage = try SeamEditor.transpose(image)
            var transposedOptions = options
            transposedOptions.masks = try transposeMaskPair(options.masks)
            let set = try await discoverMappedVerticalSeams(count: count, in: transposedImage, options: transposedOptions)
            return try MappedSeamSet(orientation: .horizontal, coordinatesBySeam: set.coordinatesBySeam)
        }
    }
}
