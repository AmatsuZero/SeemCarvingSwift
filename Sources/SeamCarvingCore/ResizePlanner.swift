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
    public var progress: (@Sendable (ResizeProgress) -> Void)?

    public init(
        energyMode: EnergyMode = .backwardSobel,
        dimensionOrder: DimensionOrder = .widthThenHeight,
        masks: MaskPair = .init(),
        progress: (@Sendable (ResizeProgress) -> Void)? = nil
    ) {
        self.energyMode = energyMode
        self.dimensionOrder = dimensionOrder
        self.masks = masks
        self.progress = progress
    }
}
