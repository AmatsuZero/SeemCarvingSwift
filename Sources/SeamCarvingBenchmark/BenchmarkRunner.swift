import Foundation
#if canImport(Darwin)
import Darwin
#endif
import SeamCarvingCore
@_spi(Backend) import SeamCarvingCore
@_spi(Benchmark) import SeamCarvingCore
import SeamCarvingAccelerate
import SeamCarvingMetal
import SeamCarvingApple

public struct BenchmarkRunner {
    public let sizes: [(Int, Int)]
    public let seams: [String]
    public let energies: [EnergyMode]
    public let backends: [String]
    public let warmup: Int
    public let iterations: Int

    public init(sizes: [(Int, Int)], seams: [String], energies: [EnergyMode], backends: [String], warmup: Int, iterations: Int) {
        self.sizes = sizes
        self.seams = seams
        self.energies = energies
        self.backends = backends
        self.warmup = warmup
        self.iterations = iterations
    }

    public func run() async throws -> BenchmarkReport {
        var results: [BenchmarkResult] = []
        for (width, height) in sizes {
            for seamSpec in seams {
                let seamCount = try resolveSeamCount(seamSpec, width: width, height: height)
                for energy in energies {
                    for backendName in backends {
                        let result = try await benchmark(size: (width, height), seams: seamCount, seamLabel: seamSpec, energy: energy, backend: backendName)
                        results.append(result)
                    }
                }
            }
        }
        return BenchmarkReport(
            schemaVersion: 1,
            hardware: hardwareName(),
            os: osVersion(),
            swift: swiftVersion(),
            xcode: xcodeVersion(),
            results: results
        )
    }

    private func benchmark(size: (Int, Int), seams: Int, seamLabel: String, energy: EnergyMode, backend: String) async throws -> BenchmarkResult {
        let image = try Self.generateImage(width: size.0, height: size.1, seed: 42)
        let target = try PixelSize(width: max(1, size.0 - seams), height: max(1, size.1 - seams))

        let instrumented: any InstrumentedSeamCarvingBackend = try makeBackend(backend)
        let options = ResizeOptions(energyMode: energy)
        let reportBackend = (instrumented as? MetalBackend)?.effectiveIdentifier(
            from: try PixelSize(width: size.0, height: size.1), to: target, options: options
        ) ?? backend

        var durations: [BackendPhaseDurations] = []
        for _ in 0..<warmup {
            _ = try await instrumented.benchmarkResize(image, to: target, options: options)
        }
        for _ in 0..<iterations {
            let bridgeStart = DispatchTime.now().uptimeNanoseconds
            let encoded = try CGImageBridge.encode(image)
            _ = try CGImageBridge.decode(encoded)
            let bridgeNS = DispatchTime.now().uptimeNanoseconds - bridgeStart
            let (_, d) = try await instrumented.benchmarkResize(image, to: target, options: options)
            var measured = d
            measured.bridgeNS = bridgeNS
            durations.append(measured)
        }

        let peak = durations.map(\.peakScratchBytes).max() ?? 0
        return BenchmarkResult(
            size: "\(size.0)x\(size.1)",
            seams: seamLabel,
            energy: energy == .backwardSobel ? "backward" : "forward",
            backend: reportBackend,
            phaseSummaries: BenchmarkPhases.summarize(durations),
            peakScratchBytes: peak
        )
    }

    private func resolveSeamCount(_ value: String, width: Int, height: Int) throws -> Int {
        if value.hasSuffix("%"), let percent = Double(value.dropLast()), percent > 0, percent <= 100 {
            return max(1, Int((Double(min(width, height)) * percent / 100.0).rounded(.down)))
        }
        guard let count = Int(value), count > 0 else {
            throw SeamCarvingError.invalidConfiguration("invalid seam count \(value)")
        }
        guard count < min(width, height) else {
            throw SeamCarvingError.invalidConfiguration("seam count \(count) must be smaller than both image dimensions")
        }
        return count
    }

    private func makeBackend(_ name: String) throws -> any InstrumentedSeamCarvingBackend {
        switch name {
        case "cpu": return CPUBackend()
        case "accelerate": return AccelerateBackend()
        case "metal-hybrid":
            let context = try MetalContext.makeDefault()
            return MetalBackend(context: context, mode: .hybrid)
        case "metal-full":
            let context = try MetalContext.makeDefault()
            return MetalBackend(context: context, mode: .full)
        default:
            throw SeamCarvingError.invalidConfiguration("unknown backend \(name)")
        }
    }

    // MARK: - Fixtures and environment

    public static func generateImage(width: Int, height: Int, seed: UInt64) throws -> RGBA8Image {
        var state = seed
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(state % 256)
            pixels += [v, v, v, 255]
        }
        return try RGBA8Image(width: width, height: height, pixels: pixels)
    }

    private func hardwareName() -> String {
        var size = 0
        #if canImport(Darwin)
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "unknown"
        #endif
    }

    private func osVersion() -> String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private func swiftVersion() -> String {
        "6"
    }

    private func xcodeVersion() -> String {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.split(separator: "\n").first.map(String.init) ?? "unknown"
        } catch {
            return "unknown"
        }
        #else
        return "unknown"
        #endif
    }
}
