import XCTest
@preconcurrency import Metal
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
import SeamCarvingAccelerate
import SeamCarvingMetal

final class PerformanceTests: XCTestCase {
    func testMetalShrinkSmoke() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }
        let context = try MetalContext.makeDefault()
        let image = try Self.randomImage(width: 32, height: 32, seed: 3)
        let result = try await MetalBackend(context: context, mode: .hybrid).resize(image, to: try PixelSize(width: 24, height: 24), options: .init())
        XCTAssertEqual(result.width, 24)
        XCTAssertEqual(result.height, 24)
    }

    #if os(iOS)
    func testDeviceBackendScreening() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device") }

        // Keep the device screening short enough for an XCTest run. The
        // desktop benchmark remains responsible for the larger 4K matrix.
        let image = try Self.randomImage(width: 1280, height: 720, seed: 42)
        let seamCounts = [1, 8]
        let energies: [EnergyMode] = [.backwardSobel, .forwardLuma]
        let backendNames = ["cpu", "accelerate", "metal-hybrid", "metal-full"]
        let totalCases = seamCounts.count * energies.count * backendNames.count
        var completedCases = 0

        print("[device-benchmark] \(totalCases) cases; direct resize, one sample")
        for seamCount in seamCounts {
            let target = try PixelSize(width: image.width - seamCount, height: image.height - seamCount)
            for energy in energies {
                var options = ResizeOptions()
                options.energyMode = energy
                for backendName in backendNames {
                    print("[device-benchmark] starting seams=\(seamCount) energy=\(energy) backend=\(backendName)")
                    let backend = try await Self.makeBackend(named: backendName)
                    let start = DispatchTime.now().uptimeNanoseconds
                    _ = try await backend.resize(image, to: target, options: options)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start
                    completedCases += 1
                    let energyName = energy == .backwardSobel ? "backward" : "forward"
                    print("[device-benchmark] [\(completedCases)/\(totalCases)] seams=\(seamCount) energy=\(energyName) backend=\(backendName) elapsed=\(Double(elapsed) / 1_000_000.0)ms")
                }
            }
        }
    }

    private static func makeBackend(named name: String) async throws -> any SeamCarvingBackend {
        switch name {
        case "cpu":
            return CPUBackend()
        case "accelerate":
            return AccelerateBackend()
        case "metal-hybrid":
            return MetalBackend(context: try MetalContext.makeDefault(), mode: .hybrid)
        case "metal-full":
            return MetalBackend(context: try MetalContext.makeDefault(), mode: .full)
        default:
            throw SeamCarvingError.invalidConfiguration("unknown benchmark backend \(name)")
        }
    }
    #endif

    static func randomImage(width: Int, height: Int, seed: UInt64) throws -> RGBA8Image {
        var state = seed
        var pixels = [UInt8]()
        for _ in 0..<(width * height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(state % 256)
            pixels += [v, v, v, 255]
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }
}
