import XCTest
@testable import WasmBridgeCore

final class WasmBridgeCoreTests: XCTestCase {
    func testResizeRGBA8ShrinksAndPreservesOutputLayout() async throws {
        let request = ResizeRGBA8Request(
            pixels: [255, 0, 0, 255, 0, 255, 0, 128],
            sourceWidth: 2,
            sourceHeight: 1,
            targetWidth: 1,
            targetHeight: 1
        )

        let result = try await resizeRGBA8(request)

        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
        XCTAssertEqual(result.pixels.count, 4)
    }

    func testResizeRGBA8RejectsWrongByteCount() async {
        let request = ResizeRGBA8Request(
            pixels: [0, 0, 0], sourceWidth: 1, sourceHeight: 1, targetWidth: 1, targetHeight: 1
        )

        await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
    }

    func testResizeRGBA8RejectsNonpositiveDimensions() async {
        let request = ResizeRGBA8Request(
            pixels: [], sourceWidth: 0, sourceHeight: 1, targetWidth: 1, targetHeight: 1
        )

        await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
    }

    func testResizeRGBA8RejectsIntegerMultiplicationOverflow() async {
        let request = ResizeRGBA8Request(
            pixels: [], sourceWidth: .max, sourceHeight: 2, targetWidth: 1, targetHeight: 1
        )

        await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
    }

    func testResizeRGBA8RejectsTargetPixelLimit() async {
        let request = ResizeRGBA8Request(
            pixels: [0, 0, 0, 255], sourceWidth: 1, sourceHeight: 1, targetWidth: 2_000_001, targetHeight: 1
        )

        await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
    }

    func testResizeRGBA8RejectsEstimatedWorkLimit() async {
        let request = ResizeRGBA8Request(
            pixels: [], sourceWidth: 2_000_000, sourceHeight: 1, targetWidth: 1_000_000, targetHeight: 1
        )

        await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
    }

    func testResizeRGBA8NoOpRoundTripPreservesPixels() async throws {
        let pixels: [UInt8] = [255, 0, 0, 17, 0, 255, 0, 203]
        let request = ResizeRGBA8Request(
            pixels: pixels, sourceWidth: 2, sourceHeight: 1, targetWidth: 2, targetHeight: 1
        )

        let result = try await resizeRGBA8(request)

        XCTAssertEqual(result.pixels, pixels)
        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 1)
    }

    func testResizeRGBA8EnlargesToRequestedDimensions() async throws {
        let request = ResizeRGBA8Request(
            pixels: [20, 40, 60, 128], sourceWidth: 1, sourceHeight: 1, targetWidth: 2, targetHeight: 2
        )

        let result = try await resizeRGBA8(request)

        XCTAssertEqual(result.width, 2)
        XCTAssertEqual(result.height, 2)
        XCTAssertEqual(result.pixels.count, 16)
    }

    func testResizeRGBA8PreservesAlphaBytesWhenEnlarging() async throws {
        let request = ResizeRGBA8Request(
            pixels: [20, 40, 60, 37], sourceWidth: 1, sourceHeight: 1, targetWidth: 2, targetHeight: 2
        )

        let result = try await resizeRGBA8(request)

        XCTAssertTrue(stride(from: 3, to: result.pixels.count, by: 4).allSatisfy { result.pixels[$0] == 37 })
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> some Any,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {}
}
