import SeamCarvingCLIModel
import SeamCarvingVision

extension FacePolicyRequest {
    func visionPolicy() throws -> FaceProtectionPolicy {
        switch self {
        case .caire:
            return .caireInspired(try CaireInspiredParameters())
        case .vision:
            return .visionQuality(try VisionQualityParameters())
        }
    }
}

extension FaceCadenceRequest {
    var visionCadence: FaceDetectionCadence {
        switch self {
        case .once: return .detectOnceAndTransformMask
        case .eachPass: return .redetectEveryPass
        }
    }
}
