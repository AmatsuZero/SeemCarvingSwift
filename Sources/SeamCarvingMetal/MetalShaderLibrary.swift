import Foundation
@preconcurrency import Metal
@_spi(Backend) import SeamCarvingCore

enum MetalShaderLibrary {
    /// Loads the compiled library emitted by SwiftPM/Xcode for every platform.
    /// Xcode does not copy the `.metal` source into simulator test bundles.
    static func makeLibrary(on device: any MTLDevice) throws -> any MTLLibrary {
        if let url = Bundle.module.url(forResource: "default", withExtension: "metallib") {
            do {
                return try device.makeLibrary(URL: url)
            } catch {
                throw SeamCarvingError.metalExecutionFailed("failed to load compiled Metal library: \(error)")
            }
        }

        guard let sourceURL = Bundle.module.url(forResource: "SeamCarving", withExtension: "metal") else {
            throw SeamCarvingError.metalExecutionFailed("Metal source and compiled library are missing from bundle")
        }
        do {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw SeamCarvingError.metalExecutionFailed("failed to compile Metal source: \(error)")
        }
    }
}
