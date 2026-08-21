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
        let energy = try adjustedEnergy(for: image, options: options)
        return try DynamicProgramming.findSeam(in: energy, orientation: orientation)
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

        var current = image
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
                seam = try await findSeam(in: current, orientation: orientation, options: options)
            case .heightThenWidth:
                orientation = remainingHorizontal > 0 ? .horizontal : .vertical
                seam = try await findSeam(in: current, orientation: orientation, options: options)
            case .adaptiveNormalizedCost:
                if remainingVertical == 0 {
                    orientation = .horizontal
                    seam = try await findSeam(in: current, orientation: orientation, options: options)
                } else if remainingHorizontal == 0 {
                    orientation = .vertical
                    seam = try await findSeam(in: current, orientation: orientation, options: options)
                } else {
                    let verticalSeam = try await findSeam(in: current, orientation: .vertical, options: options)
                    let horizontalSeam = try await findSeam(in: current, orientation: .horizontal, options: options)
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

    private func adjustedEnergy(for image: RGBA8Image, options: ResizeOptions) throws -> EnergyMap {
        switch options.energyMode {
        case .backwardSobel:
            return try backwardEnergyProvider.compute(for: image)
        case .forwardLuma:
            throw SeamCarvingError.invalidConfiguration("forward energy is not available yet")
        }
    }
}
