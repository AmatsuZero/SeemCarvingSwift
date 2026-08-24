import Foundation
@_spi(Backend) import SeamCarvingCore
import SeamCarvingAccelerate
import SeamCarvingMetal

/// Internal injectable backend selector. The Apple runtime owns backend selection
/// because SeamCarvingCore cannot depend on Accelerate or Metal.
struct BackendFactory: Sendable {
    var makeAccelerate: @Sendable () throws -> any SeamCarvingBackend
    var makeMetal: @Sendable (MetalExecutionMode) throws -> any SeamCarvingBackend
    var makeCPU: @Sendable () -> any SeamCarvingBackend

    static let `default` = BackendFactory(
        makeAccelerate: { AccelerateBackend() },
        makeMetal: { mode in
            let context = try MetalContext.makeDefault()
            return MetalBackend(context: context, mode: mode)
        },
        makeCPU: { CPUBackend() }
    )

    func make(_ configuration: AppleSeamCarverConfiguration) throws -> any SeamCarvingBackend {
        if configuration.deterministic {
            return makeCPU()
        }
        switch configuration.backend {
        case .cpu:
            return makeCPU()
        case .accelerate:
            return try makeAccelerate()
        case .metal:
            return try makeMetal(configuration.metalMode)
        case .automatic:
            do {
                return try makeMetal(configuration.metalMode)
            } catch {
                do {
                    return try makeAccelerate()
                } catch {
                    return makeCPU()
                }
            }
        }
    }
}
