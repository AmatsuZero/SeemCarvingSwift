import Foundation
import SeamCarvingCore

public enum FaceMaskRasterizer {
    /// Rasterizes face regions into a protection mask for the given pixel size.
    public static func rasterize(
        regions: [FaceRegion],
        size: PixelSize,
        policy: FaceProtectionPolicy
    ) throws -> Mask {
        let width = size.width
        let height = size.height

        let threshold: Float
        switch policy {
        case .caireInspired(let p): threshold = p.minimumConfidence
        case .visionQuality(let p): threshold = p.minimumConfidence
        }

        // Filter by confidence threshold (strictly below is excluded).
        let accepted = regions.filter { $0.confidence >= threshold }

        var values = [Float](repeating: 0, count: width * height)

        for region in accepted {
            let rect = clip(region, width: width, height: height)
            switch policy {
            case .caireInspired(let p):
                let expanded = expand(rect, fraction: p.expansionFraction, width: width, height: height)
                fillRectangle(expanded, into: &values, width: width, height: height)
            case .visionQuality(let p):
                let expanded = expand(rect, fraction: p.expansionFraction, width: width, height: height)
                fillEllipse(expanded, featherFraction: p.featherFraction, into: &values, width: width, height: height)
            }
        }

        return try Mask(width: width, height: height, values: values)
    }

    // MARK: - Geometry helpers

    private static func clip(_ region: FaceRegion, width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let x = max(0, region.x)
        let y = max(0, region.y)
        let x2 = min(width, region.x + region.width)
        let y2 = min(height, region.y + region.height)
        return (x, y, max(0, x2 - x), max(0, y2 - y))
    }

    private static func expand(_ rect: (x: Int, y: Int, width: Int, height: Int), fraction: Float, width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let dx = Int((Float(rect.width) * fraction).rounded())
        let dy = Int((Float(rect.height) * fraction).rounded())
        let x = max(0, rect.x - dx)
        let y = max(0, rect.y - dy)
        let x2 = min(width, rect.x + rect.width + dx)
        let y2 = min(height, rect.y + rect.height + dy)
        return (x, y, max(0, x2 - x), max(0, y2 - y))
    }

    private static func fillRectangle(_ rect: (x: Int, y: Int, width: Int, height: Int), into values: inout [Float], width: Int, height: Int) {
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                values[y * width + x] = 1
            }
        }
    }

    private static func fillEllipse(_ rect: (x: Int, y: Int, width: Int, height: Int), featherFraction: Float, into values: inout [Float], width: Int, height: Int) {
        let cx = Float(rect.x) + Float(rect.width) / 2
        let cy = Float(rect.y) + Float(rect.height) / 2
        let rx = Float(rect.width) / 2
        let ry = Float(rect.height) / 2
        let feather = featherFraction
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                let nx = (Float(x) - cx) / rx
                let ny = (Float(y) - cy) / ry
                let d = (nx * nx + ny * ny).squareRoot()
                if d <= 1 {
                    let falloff = feather > 0 ? min(max((1 - d) / feather, 0), 1) : 1
                    values[y * width + x] = max(values[y * width + x], falloff)
                }
            }
        }
    }
}
