import Foundation
@_spi(Backend) import SeamCarvingCore

enum MetalShaderLibrary {
    /// Loads the bundled Metal source once per process.
    static let source: String = {
        guard let url = Bundle.module.url(forResource: "SeamCarving", withExtension: "metal") else {
            fatalError("SeamCarving.metal resource not found in bundle")
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Failed to load SeamCarving.metal: \(error)")
        }
    }()
}
