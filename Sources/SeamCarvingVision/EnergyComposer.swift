import SeamCarvingCore

public enum EnergyComposer {
    /// Appends a face protection layer and zeros removal wherever the face is protected.
    public static func compose(
        userMasks: MaskPair,
        faceMask: Mask,
        policy: FaceProtectionPolicy
    ) throws -> MaskPair {
        let weight: Float
        switch policy {
        case .caireInspired(let p): weight = p.protectionWeight
        case .visionQuality(let p): weight = p.protectionWeight
        }

        var newProtection = userMasks.protectionLayers
        newProtection.append(try ProtectionLayer(mask: faceMask, strength: .soft(weight)))

        var newRemoval: Mask?
        if let removal = userMasks.removal {
            var values = removal.values
            for i in 0..<values.count where faceMask.values[i] > 0 {
                values[i] = 0
            }
            newRemoval = try Mask(width: removal.width, height: removal.height, values: values)
        }

        return try MaskPair(
            protectionLayers: newProtection,
            removal: newRemoval,
            removalWeight: userMasks.removalWeight
        )
    }
}
