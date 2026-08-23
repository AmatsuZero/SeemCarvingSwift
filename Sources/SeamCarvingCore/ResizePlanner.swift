public enum BackendPreference: Sendable, Equatable {
    case automatic
    case cpu
    case accelerate
    case metal
}

public enum MetalExecutionMode: Sendable, Equatable {
    case hybrid
    case full
}

public enum DimensionOrder: Sendable, Equatable {
    case widthThenHeight
    case heightThenWidth
    case adaptiveNormalizedCost
}

/// Strategy for pre-scaling the image before residual seam carving.
///
/// - `none`: Seam carving operates directly on the source image. This is the
///   default and preserves the exact, mask-aware seam-carving semantics.
/// - `lanczosThenExactResidual`: An intermediate Lanczos pre-scale is applied
///   to the image and every protection/removal mask, then the residual seam
///   carving reaches the exact target dimensions. This is an opt-in
///   approximation that is NOT performed implicitly in `none` mode.
public enum PreScaleStrategy: Sendable, Equatable {
    case none
    case lanczosThenExactResidual
}

public struct ResizeProgress: Sendable, Equatable {
    public let completedEdits: Int
    public let totalEdits: Int
    public let size: PixelSize

    public init(completedEdits: Int, totalEdits: Int, size: PixelSize) {
        self.completedEdits = completedEdits
        self.totalEdits = totalEdits
        self.size = size
    }
}

public enum MaskStrength: Sendable, Equatable {
    case soft(Float)
    case hard
}

public struct ProtectionLayer: Sendable, Equatable {
    public let mask: Mask
    public let strength: MaskStrength

    public init(mask: Mask, strength: MaskStrength) throws {
        switch strength {
        case .soft(let weight):
            guard weight.isFinite, weight >= 0 else {
                throw SeamCarvingError.invalidConfiguration("soft protection weight must be finite and nonnegative")
            }
        case .hard:
            break
        }
        self.mask = mask
        self.strength = strength
    }
}

public struct MaskPair: Sendable {
    public let protectionLayers: [ProtectionLayer]
    public let removal: Mask?
    public let removalWeight: Float

    public init() {
        self.protectionLayers = []
        self.removal = nil
        self.removalWeight = 1_000
    }

    public init(protectionLayers: [ProtectionLayer], removal: Mask?, removalWeight: Float) throws {
        for layer in protectionLayers {
            switch layer.strength {
            case .soft(let weight):
                guard weight.isFinite, weight >= 0 else {
                    throw SeamCarvingError.invalidConfiguration("soft protection weight must be finite and nonnegative")
                }
            case .hard:
                break
            }
        }
        guard removalWeight.isFinite, removalWeight >= 0 else {
            throw SeamCarvingError.invalidConfiguration("removal weight must be finite and nonnegative")
        }
        self.protectionLayers = protectionLayers
        self.removal = removal
        self.removalWeight = removalWeight
    }
}

public struct ResizeOptions: Sendable {
    public var energyMode: EnergyMode
    public var dimensionOrder: DimensionOrder
    public var masks: MaskPair
    public var preScaleStrategy: PreScaleStrategy
    /// Box-blur radius applied to the luma plane before backward (Sobel) energy.
    /// `0` means no blur and reproduces the default result. Only the backward
    /// Sobel energy honors this control.
    public var blurRadius: Int
    /// Sobel gradient-magnitude threshold for backward energy: magnitudes below
    /// this value are zeroed. `0` means no threshold and reproduces the default
    /// result. Only the backward Sobel energy honors this control.
    public var sobelThreshold: Float
    public var progress: (@Sendable (ResizeProgress) -> Void)?
    /// Optional seam observation hook for debug artifact generation.
    ///
    /// Default is `nil`. Core emits observations only when this hook is set,
    /// and an error thrown by the hook (including `CancellationError`) stops the
    /// resize before the observed seam is applied.
    public var seamObserver: (@Sendable (SeamObservation) throws -> Void)?

    public init(
        energyMode: EnergyMode = .backwardSobel,
        dimensionOrder: DimensionOrder = .widthThenHeight,
        masks: MaskPair = .init(),
        preScaleStrategy: PreScaleStrategy = .none,
        blurRadius: Int = 0,
        sobelThreshold: Float = 0,
        progress: (@Sendable (ResizeProgress) -> Void)? = nil,
        seamObserver: (@Sendable (SeamObservation) throws -> Void)? = nil
    ) {
        self.energyMode = energyMode
        self.dimensionOrder = dimensionOrder
        self.masks = masks
        self.preScaleStrategy = preScaleStrategy
        self.blurRadius = blurRadius
        self.sobelThreshold = sobelThreshold
        self.progress = progress
        self.seamObserver = seamObserver
    }
}
