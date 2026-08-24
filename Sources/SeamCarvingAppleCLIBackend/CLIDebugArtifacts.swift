import CoreGraphics
import Foundation
import SeamCarvingAppleImaging
import SeamCarvingCLIModel
import SeamCarvingCore

struct SeamDebugArtifactConfiguration: Sendable, Equatable {
    let directory: URL
    let color: SeamColor
    let shape: SeamShape
    let requestedBackend: BackendPreference
    let effectiveBackend: BackendPreference
    let backendDowngradeReason: String?
}

final class SeamObservationCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [SeamObservation] = []

    func append(_ observation: SeamObservation) {
        lock.lock()
        observations.append(observation)
        lock.unlock()
    }

    var values: [SeamObservation] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }
}

enum CLIDebugArtifactWriter {
    static func write(
        observations: [SeamObservation],
        sourceSize: PixelSize,
        targetSize: PixelSize,
        configuration: SeamDebugArtifactConfiguration
    ) throws {
        try FileManager.default.createDirectory(
            at: configuration.directory,
            withIntermediateDirectories: true
        )

        var seamEntries: [[String: Any]] = []
        for observation in observations {
            try Task.checkCancellation()
            let fileName = String(format: "seam-%04d.png", observation.index)
            let overlay = try SeamOverlayRenderer.render(
                observation: observation,
                color: configuration.color.rgba8,
                shape: configuration.shape
            )
            let cgImage = try CGImageBridge.encode(overlay)
            try CLIImageIO.writeImage(
                cgImage,
                toPath: configuration.directory.appendingPathComponent(fileName).path,
                format: .png
            )

            seamEntries.append([
                "index": observation.index,
                "totalCount": observation.totalCount,
                "kind": observation.kind.rawValue,
                "orientation": observation.seam.orientation.cliDebugName,
                "imageWidth": observation.imageBeforeEdit.width,
                "imageHeight": observation.imageBeforeEdit.height,
                "coordinates": observation.seam.coordinates.map(Int.init),
                "overlay": fileName,
            ])
        }

        var manifest: [String: Any] = [
            "schemaVersion": 1,
            "coordinateSpace": "current-image-before-edit-top-left",
            "sourceWidth": sourceSize.width,
            "sourceHeight": sourceSize.height,
            "targetWidth": targetSize.width,
            "targetHeight": targetSize.height,
            "seamColor": configuration.color.hexRGBA,
            "seamShape": configuration.shape.rawValue,
            "requestedBackend": configuration.requestedBackend.cliDebugName,
            "effectiveBackend": configuration.effectiveBackend.cliDebugName,
            "seams": seamEntries,
        ]
        if let reason = configuration.backendDowngradeReason {
            manifest["backendDowngradeReason"] = reason
        }

        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        do {
            try data.write(to: configuration.directory.appendingPathComponent("manifest.json"), options: .atomic)
        } catch {
            throw CLIImageIOError.cannotWriteOutput(configuration.directory.appendingPathComponent("manifest.json").path)
        }
    }
}

enum SeamOverlayRenderer {
    static func render(
        observation: SeamObservation,
        color: RGBA8,
        shape: SeamShape
    ) throws -> RGBA8Image {
        var overlay = observation.imageBeforeEdit
        let points = try seamPoints(observation.seam, width: overlay.width, height: overlay.height)
        switch shape {
        case .points:
            for point in points {
                blend(color, into: &overlay, x: point.x, y: point.y)
            }
        case .line:
            guard var previous = points.first else { return overlay }
            blend(color, into: &overlay, x: previous.x, y: previous.y)
            for point in points.dropFirst() {
                drawLine(from: previous, to: point, color: color, image: &overlay)
                previous = point
            }
        }
        return overlay
    }

    private static func seamPoints(_ seam: SeamPath, width: Int, height: Int) throws -> [(x: Int, y: Int)] {
        switch seam.orientation {
        case .vertical:
            guard seam.coordinates.count == height else { throw SeamCarvingError.invalidSeam }
            return try seam.coordinates.enumerated().map { y, rawX in
                let x = Int(rawX)
                guard x >= 0, x < width else { throw SeamCarvingError.invalidSeam }
                return (x, y)
            }
        case .horizontal:
            guard seam.coordinates.count == width else { throw SeamCarvingError.invalidSeam }
            return try seam.coordinates.enumerated().map { x, rawY in
                let y = Int(rawY)
                guard y >= 0, y < height else { throw SeamCarvingError.invalidSeam }
                return (x, y)
            }
        }
    }

    private static func drawLine(from start: (x: Int, y: Int), to end: (x: Int, y: Int), color: RGBA8, image: inout RGBA8Image) {
        let dx = abs(end.x - start.x)
        let dy = -abs(end.y - start.y)
        let sx = start.x < end.x ? 1 : -1
        let sy = start.y < end.y ? 1 : -1
        var error = dx + dy
        var x = start.x
        var y = start.y

        while true {
            blend(color, into: &image, x: x, y: y)
            if x == end.x, y == end.y { break }
            let e2 = 2 * error
            if e2 >= dy {
                error += dy
                x += sx
            }
            if e2 <= dx {
                error += dx
                y += sy
            }
        }
    }

    private static func blend(_ color: RGBA8, into image: inout RGBA8Image, x: Int, y: Int) {
        guard x >= 0, x < image.width, y >= 0, y < image.height else { return }
        let base = image[x, y]
        let alpha = UInt16(color.a)
        let inverse = UInt16(255 - color.a)
        image[x, y] = RGBA8(
            r: UInt8((UInt16(color.r) * alpha + UInt16(base.r) * inverse + 127) / 255),
            g: UInt8((UInt16(color.g) * alpha + UInt16(base.g) * inverse + 127) / 255),
            b: UInt8((UInt16(color.b) * alpha + UInt16(base.b) * inverse + 127) / 255),
            a: base.a
        )
    }
}

private extension SeamOrientation {
    var cliDebugName: String {
        switch self {
        case .vertical: return "vertical"
        case .horizontal: return "horizontal"
        }
    }
}

private extension BackendPreference {
    var cliDebugName: String {
        switch self {
        case .automatic: return "automatic"
        case .cpu: return "cpu"
        case .accelerate: return "accelerate"
        case .metal: return "metal"
        }
    }
}
