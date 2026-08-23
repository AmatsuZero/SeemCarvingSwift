import CoreGraphics
import Vision
import SeamCarvingCore

/// Converts a normalized bottom-left-origin Vision bounding box to an upright,
/// top-left-origin half-open pixel rectangle.
func uprightRect(from box: CGRect, imageWidth: Int, imageHeight: Int) -> (x: Int, y: Int, width: Int, height: Int) {
    let x0 = Int(floor(box.minX * CGFloat(imageWidth)))
    let x1 = Int(ceil(box.maxX * CGFloat(imageWidth)))
    let y0 = Int(floor((1 - box.maxY) * CGFloat(imageHeight)))
    let y1 = Int(ceil((1 - box.minY) * CGFloat(imageHeight)))
    return (x0, y0, x1 - x0, y1 - y0)
}

public struct VisionFaceDetector: FaceDetecting, Sendable {
    private let revision: Int

    /// Uses the newest face-rectangle revision available on the running OS.
    /// This keeps the app portable across Apple platforms while still allowing
    /// callers to pin a revision for reproducible tests.
    public init() throws {
        guard let revision = VNDetectFaceRectanglesRequest.supportedRevisions.max() else {
            throw SeamCarvingError.invalidConfiguration("Vision face detection is unavailable")
        }
        self.revision = revision
    }

    public init(revision: Int) throws {
        guard VNDetectFaceRectanglesRequest.supportedRevisions.contains(revision) else {
            throw SeamCarvingError.invalidConfiguration("unsupported Vision revision \(revision)")
        }
        self.revision = revision
    }

    public func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion] {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = revision
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let results = request.results else {
            return []
        }
        let width = image.width
        let height = image.height
        return try results.compactMap { observation in
            let rect = uprightRect(from: observation.boundingBox, imageWidth: width, imageHeight: height)
            guard rect.width > 0, rect.height > 0 else { return nil }
            return try FaceRegion(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height,
                confidence: observation.confidence
            )
        }
    }
}
