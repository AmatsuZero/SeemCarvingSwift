import Foundation
@_spi(Benchmark) import SeamCarvingCore

public struct PhaseSummary: Codable, Equatable {
    public let p50NS: UInt64
    public let p95NS: UInt64
    public let rawNS: [UInt64]

    public init(p50NS: UInt64, p95NS: UInt64, rawNS: [UInt64]) {
        self.p50NS = p50NS
        self.p95NS = p95NS
        self.rawNS = rawNS
    }
}

public struct BenchmarkResult: Codable, Equatable {
    public let size: String
    public let seams: String
    public let energy: String
    public let backend: String
    public let phaseSummaries: [String: PhaseSummary]
    public let peakScratchBytes: UInt64

    public init(size: String, seams: String, energy: String, backend: String, phaseSummaries: [String: PhaseSummary], peakScratchBytes: UInt64) {
        self.size = size
        self.seams = seams
        self.energy = energy
        self.backend = backend
        self.phaseSummaries = phaseSummaries
        self.peakScratchBytes = peakScratchBytes
    }
}

public struct BenchmarkReport: Codable {
    public let schemaVersion: Int
    public let hardware: String
    public let os: String
    public let swift: String
    public let xcode: String
    public let results: [BenchmarkResult]

    public init(schemaVersion: Int, hardware: String, os: String, swift: String, xcode: String = "unknown", results: [BenchmarkResult]) {
        self.schemaVersion = schemaVersion
        self.hardware = hardware
        self.os = os
        self.swift = swift
        self.xcode = xcode
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hardware, os, swift, xcode, results
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        hardware = try container.decode(String.self, forKey: .hardware)
        os = try container.decode(String.self, forKey: .os)
        swift = try container.decode(String.self, forKey: .swift)
        xcode = try container.decodeIfPresent(String.self, forKey: .xcode) ?? "unknown"
        results = try container.decode([BenchmarkResult].self, forKey: .results)
    }
}

public enum Percentile {
    /// Nearest-rank percentile: `ceil(p * n) - 1` over sorted values.
    public static func nearestRank(_ values: [UInt64], percentile: Double) -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(ceil(percentile * Double(sorted.count))) - 1
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    public static func p50(_ values: [UInt64]) -> UInt64 {
        nearestRank(values, percentile: 0.50)
    }

    public static func p95(_ values: [UInt64]) -> UInt64 {
        nearestRank(values, percentile: 0.95)
    }
}

enum BenchmarkPhases {
    static let all = ["bridge", "energy", "mask", "dynamicProgramming", "backtrack", "edit", "commandEncoding", "gpuWait", "total"]

    static func summarize(_ durations: [BackendPhaseDurations]) -> [String: PhaseSummary] {
        let keys: [(String, KeyPath<BackendPhaseDurations, UInt64>)] = [
            ("bridge", \.bridgeNS),
            ("energy", \.energyNS),
            ("mask", \.maskNS),
            ("dynamicProgramming", \.dynamicProgrammingNS),
            ("backtrack", \.backtrackNS),
            ("edit", \.editNS),
            ("commandEncoding", \.commandEncodingNS),
            ("gpuWait", \.gpuWaitNS),
            ("total", \.totalNS),
        ]
        var summaries: [String: PhaseSummary] = [:]
        for (name, keyPath) in keys {
            let raw = durations.map { $0[keyPath: keyPath] }
            summaries[name] = PhaseSummary(p50NS: Percentile.p50(raw), p95NS: Percentile.p95(raw), rawNS: raw)
        }
        return summaries
    }
}
