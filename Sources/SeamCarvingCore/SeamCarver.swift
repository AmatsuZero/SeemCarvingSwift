public struct SeamCarver: Sendable {
    private let backend: any SeamCarvingBackend

    public init() {
        self.backend = CPUBackend()
    }

    @_spi(Backend)
    public init(backend: any SeamCarvingBackend) {
        self.backend = backend
    }

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image {
        try await backend.resize(image, to: target, options: options)
    }
}

public extension SeamCarver {
    /// Removes the object marked by `removalMask` by carving seams that cross it,
    /// optionally restoring the original size afterwards.
    func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image {
        guard removalMask.width == image.width, removalMask.height == image.height else {
            throw SeamCarvingError.invalidConfiguration("removal mask dimensions must match image")
        }

        var currentImage = image
        var currentRemoval = removalMask
        var currentProtection = options.masks.protectionLayers
        var completedEdits = 0
        let totalEdits = max(1, removalMask.values.reduce(into: 0) { $0 += $1 > 0 ? 1 : 0 })

        while currentRemoval.values.contains(where: { $0 > 0 }) {
            try Task.checkCancellation()

            let masks = try MaskPair(
                protectionLayers: currentProtection,
                removal: currentRemoval,
                removalWeight: options.masks.removalWeight
            )
            var effectiveOptions = options
            effectiveOptions.masks = masks

            let verticalSeam = try await backend.findSeam(in: currentImage, orientation: .vertical, options: effectiveOptions)
            let horizontalSeam = try await backend.findSeam(in: currentImage, orientation: .horizontal, options: effectiveOptions)

            let verticalCrosses = Self.seamCrossesRemoval(verticalSeam, currentRemoval)
            let horizontalCrosses = Self.seamCrossesRemoval(horizontalSeam, currentRemoval)

            let chosen: SeamPath
            if verticalCrosses && horizontalCrosses {
                let verticalNormalized = verticalSeam.totalCost / Float(currentImage.height)
                let horizontalNormalized = horizontalSeam.totalCost / Float(currentImage.width)
                chosen = verticalNormalized <= horizontalNormalized ? verticalSeam : horizontalSeam
            } else if verticalCrosses {
                chosen = verticalSeam
            } else if horizontalCrosses {
                chosen = horizontalSeam
            } else {
                throw SeamCarvingError.noFeasibleSeam
            }

            currentImage = try SeamEditor.remove(chosen, from: currentImage)
            currentRemoval = try SeamEditor.remove(chosen, from: currentRemoval)
            currentProtection = try currentProtection.map { layer in
                let newMask = try SeamEditor.remove(chosen, from: layer.mask)
                return try ProtectionLayer(mask: newMask, strength: layer.strength)
            }
            completedEdits += 1
            options.progress?(ResizeProgress(
                completedEdits: completedEdits,
                totalEdits: totalEdits,
                size: try PixelSize(width: currentImage.width, height: currentImage.height)
            ))
        }

        if restoreOriginalSize {
            let originalSize = try PixelSize(width: image.width, height: image.height)
            var restoreOptions = options
            restoreOptions.masks = try MaskPair(
                protectionLayers: currentProtection,
                removal: nil,
                removalWeight: options.masks.removalWeight
            )
            return try await backend.resize(currentImage, to: originalSize, options: restoreOptions)
        }

        return currentImage
    }

    private static func seamCrossesRemoval(_ seam: SeamPath, _ removal: Mask) -> Bool {
        switch seam.orientation {
        case .vertical:
            for (y, x) in seam.coordinates.enumerated() where removal[Int(x), y] > 0 {
                return true
            }
        case .horizontal:
            for (x, y) in seam.coordinates.enumerated() where removal[x, Int(y)] > 0 {
                return true
            }
        }
        return false
    }
}
