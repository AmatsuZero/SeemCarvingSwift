import CoreGraphics
import Foundation
import SeamCarvingCore

public struct FaceRegion: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let confidence: Float

    public init(x: Int, y: Int, width: Int, height: Int, confidence: Float) throws {
        guard x >= 0, y >= 0, width > 0, height > 0 else {
            throw SeamCarvingError.invalidConfiguration("invalid face region origin or size")
        }
        let (_, overflowX) = x.addingReportingOverflow(width)
        let (_, overflowY) = y.addingReportingOverflow(height)
        guard !overflowX, !overflowY else {
            throw SeamCarvingError.invalidConfiguration("face region overflows")
        }
        guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
            throw SeamCarvingError.invalidConfiguration("confidence must be finite within 0...1")
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

public protocol FaceDetecting: Sendable {
    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion]
}

public struct CaireInspiredParameters: Sendable, Equatable {
    public var expansionFraction: Float
    public var protectionWeight: Float
    public var minimumConfidence: Float

    public init(
        expansionFraction: Float = 0.10,
        protectionWeight: Float = 1_000,
        minimumConfidence: Float = 0.0
    ) throws {
        guard expansionFraction.isFinite, expansionFraction >= 0 else {
            throw SeamCarvingError.invalidConfiguration("expansionFraction must be finite and nonnegative")
        }
        guard protectionWeight.isFinite, protectionWeight >= 0 else {
            throw SeamCarvingError.invalidConfiguration("protectionWeight must be finite and nonnegative")
        }
        guard minimumConfidence.isFinite, minimumConfidence >= 0, minimumConfidence <= 1 else {
            throw SeamCarvingError.invalidConfiguration("minimumConfidence must be finite within 0...1")
        }
        self.expansionFraction = expansionFraction
        self.protectionWeight = protectionWeight
        self.minimumConfidence = minimumConfidence
    }
}

public struct VisionQualityParameters: Sendable, Equatable {
    public var expansionFraction: Float
    public var featherFraction: Float
    public var protectionWeight: Float
    public var minimumConfidence: Float

    public init(
        expansionFraction: Float = 0.20,
        featherFraction: Float = 0.30,
        protectionWeight: Float = 1_000,
        minimumConfidence: Float = 0.0
    ) throws {
        guard expansionFraction.isFinite, expansionFraction >= 0 else {
            throw SeamCarvingError.invalidConfiguration("expansionFraction must be finite and nonnegative")
        }
        guard featherFraction.isFinite, featherFraction >= 0, featherFraction <= 1 else {
            throw SeamCarvingError.invalidConfiguration("featherFraction must be finite within 0...1")
        }
        guard protectionWeight.isFinite, protectionWeight >= 0 else {
            throw SeamCarvingError.invalidConfiguration("protectionWeight must be finite and nonnegative")
        }
        guard minimumConfidence.isFinite, minimumConfidence >= 0, minimumConfidence <= 1 else {
            throw SeamCarvingError.invalidConfiguration("minimumConfidence must be finite within 0...1")
        }
        self.expansionFraction = expansionFraction
        self.featherFraction = featherFraction
        self.protectionWeight = protectionWeight
        self.minimumConfidence = minimumConfidence
    }
}

public enum FaceProtectionPolicy: Sendable, Equatable {
    case caireInspired(CaireInspiredParameters)
    case visionQuality(VisionQualityParameters)
}

public enum FaceDetectionCadence: Sendable, Equatable {
    case detectOnceAndTransformMask
    case redetectEveryPass
}
