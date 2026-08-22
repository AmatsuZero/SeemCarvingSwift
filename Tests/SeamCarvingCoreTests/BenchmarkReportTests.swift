import XCTest
@_spi(Benchmark) import SeamCarvingCore
@testable import SeamCarvingBenchmark

final class BenchmarkReportTests: XCTestCase {
    func testPercentileNearestRank() {
        XCTAssertEqual(Percentile.p50([10, 20, 30, 40, 50]), 30)
        XCTAssertEqual(Percentile.p95([10, 20, 30, 40, 50]), 50)
        XCTAssertEqual(Percentile.p50([5, 1, 4, 2, 3]), 3)
    }

    func testPercentileSingleValue() {
        XCTAssertEqual(Percentile.p50([42]), 42)
        XCTAssertEqual(Percentile.p95([42]), 42)
    }

    func testPercentileEmpty() {
        XCTAssertEqual(Percentile.p50([]), 0)
    }

    func testReportSchemaVersion() throws {
        let report = BenchmarkReport(schemaVersion: 1, hardware: "h", os: "o", swift: "6", xcode: "Xcode 26", results: [])
        let data = try JSONEncoder().encode(report)
        let object = try JSONSerialization.jsonObject(with: data)
        let dict = object as? [String: Any]
        XCTAssertEqual(dict?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(dict?["xcode"] as? String, "Xcode 26")
    }

    func testPhaseSummariesCoverAllPhases() throws {
        let durations: [BackendPhaseDurations] = (0..<5).map { i in
            let value = UInt64(i)
            return BackendPhaseDurations(
                bridgeNS: value, energyNS: value, maskNS: value, dynamicProgrammingNS: value,
                backtrackNS: value, editNS: value, commandEncodingNS: value, gpuWaitNS: value,
                totalNS: value, peakScratchBytes: value
            )
        }
        let summaries = BenchmarkPhases.summarize(durations)
        XCTAssertEqual(Set(summaries.keys), Set(BenchmarkPhases.all))
        for (_, summary) in summaries {
            XCTAssertEqual(summary.rawNS.count, 5)
        }
    }
}
