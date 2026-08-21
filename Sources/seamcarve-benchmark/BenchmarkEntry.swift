import Foundation
import SeamCarvingCore
import SeamCarvingBenchmark

@main
enum BenchmarkEntry {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options = try parse(arguments)

        let runner = BenchmarkRunner(
            sizes: options.sizes,
            seams: options.seams,
            energies: options.energies,
            backends: options.backends,
            warmup: options.warmup,
            iterations: options.iterations
        )
        let report = try await runner.run()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: URL(fileURLWithPath: options.output))
    }

    private struct ParsedOptions {
        var sizes: [(Int, Int)] = []
        var seams: [String] = []
        var energies: [EnergyMode] = [.backwardSobel]
        var backends: [String] = ["cpu"]
        var warmup = 3
        var iterations = 10
        var output = "/tmp/seam-carving-benchmark.json"
    }

    private static func parse(_ arguments: [String]) throws -> ParsedOptions {
        var result = ParsedOptions()
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            func next() throws -> String {
                guard index + 1 < arguments.count else { throw NSError(domain: "benchmark", code: 1) }
                index += 1
                return arguments[index]
            }
            switch arg {
            case "--sizes":
                let value = try next()
                result.sizes = value.split(separator: ",").compactMap { part -> (Int, Int)? in
                    let dims = part.split(separator: "x")
                    guard dims.count == 2, let w = Int(dims[0]), let h = Int(dims[1]) else { return nil }
                    return (w, h)
                }
            case "--seams":
                let value = try next()
                result.seams = value.split(separator: ",").map(String.init)
            case "--energies":
                let value = try next()
                result.energies = value.split(separator: ",").map { $0 == "forward" ? .forwardLuma : .backwardSobel }
            case "--backends":
                let value = try next()
                result.backends = value.split(separator: ",").map(String.init)
            case "--warmup":
                result.warmup = Int(try next()) ?? 3
            case "--iterations":
                result.iterations = Int(try next()) ?? 10
            case "--output":
                result.output = try next()
            default:
                break
            }
            index += 1
        }
        return result
    }
}
