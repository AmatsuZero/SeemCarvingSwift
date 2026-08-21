# Seam Carving Swift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-oriented Swift Package for content-aware image shrinking and enlargement on iOS and macOS, with a deterministic CPU reference, Accelerate CPU optimization, an opt-in Metal backend, Apple image bridges, tests, and benchmarks.

**Architecture:** `SeamCarvingCore` owns all algorithm semantics, the CPU oracle, and a narrow backend SPI. `SeamCarvingAccelerate` replaces only CPU-friendly image operations, while `SeamCarvingMetal` implements GPU-resident kernels behind the same semantics. `SeamCarvingApple` composes backends and bridges Core Graphics, Core Image, and Core Video; the optional `SeamCarvingVision` target converts Vision face observations into ordinary Core masks without making Core depend on Vision.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Core Graphics, Accelerate/vImage/vDSP, Metal compute, Core Image, Core Video, optional Vision face detection, `os.signpost`.

**Spec:** `docs/ios-macos-seam-carving-implementation-research.md`

## Global Constraints

- Use `swift-tools-version: 6.0`, iOS 17+, and macOS 14+.
- Keep `SeamCarvingCore` independent of UIKit, AppKit, Core Image, Core Video, Accelerate, and Metal.
- Do not add third-party runtime dependencies.
- Do not create or assume a project license; package publication remains gated on the owner selecting and adding one outside this plan.
- Do not add MLX or Core ML integration. Vision is confined to the optional `SeamCarvingVision` target; `SeamCarvingCore` must not import or conditionally compile against Vision.
- Treat the upstream MATLAB repository as an algorithm reference only. Do not copy its implementation; it contains known indexing and visualization defects.
- Internally normalize images to upright, origin-zero, sRGB-encoded straight-alpha RGBA8 and calculate linear luma/energy/cumulative cost with `Float32`.
- Calculate default luma from linear-sRGB components with `0.2126R + 0.7152G + 0.0722B`.
- Define backward energy as 3×3 Sobel with `abs(gx) + abs(gy)` and clamp-to-edge boundaries.
- Resolve equal predecessor costs by choosing the smallest predecessor x. CPU, Accelerate, and Metal must implement this same tie-break.
- Use exact sequential seam discovery by default. Any approximate batch behavior is outside this plan.
- Never block the main actor waiting for Metal. Use command-buffer completion with a checked continuation.
- Check cancellation between seam iterations. Report progress after every committed seam edit.
- Treat Caire as behavior/reference material only. Do not copy source code or use it as a dependency.
- Face-aware behavior flows only through `FaceDetecting -> FaceRegion -> FaceMaskRasterizer -> EnergyComposer`; face masks use the same upright canonical pixel coordinates as image/mask editing and face protection overrides removal energy.
- Every task follows red-green-refactor, ends with the listed verification, and commits only the files named by that task.
- Before implementation, create an isolated worktree with `superpowers:using-git-worktrees` unless the user explicitly chooses the current worktree.

## Scope Delivered by This Plan

- Exact shrink and enlarge in width and height.
- Backward Sobel and forward-luma energy.
- Protect and removal masks, including object removal followed by optional size restoration.
- Pure Swift CPU backend, Accelerate hybrid backend, Metal hybrid/full backend.
- `RGBA8Image`, `CGImage`, `CIImage`, and `CVPixelBuffer` entry points.
- Optional Vision face protection with fixed revisions, Caire-compatible and quality-oriented raster policies, and configurable detection cadence.
- Async cancellation, progress, deterministic mode, backend selection.
- Unit, property-style, backend parity, integration, and performance tests.

## Explicit Non-Goals

- Video temporal coherence.
- Learned saliency or semantic segmentation.
- MLX or Core ML runtime dependencies. Vision is an optional Apple-only face-protection adapter, never a Core dependency.
- Transport-map optimal width/height ordering.
- Approximate simultaneous multi-seam discovery.
- Lanczos or other conventional pre-scaling before seam carving. V1 defaults to exact seam semantics; any future pre-scale stage must be explicit opt-in and separately benchmarked/documented.
- HDR/extended-range input. The first release rejects it with `.unsupportedDynamicRange`; it never silently clamps or tone maps.
- Intel/discrete-GPU-specific optimization beyond correct Metal storage-mode behavior.

## Locked File Structure

```text
Package.swift
Sources/
├── SeamCarvingCore/
│   ├── RGBA8Image.swift
│   ├── Mask.swift
│   ├── Geometry.swift
│   ├── Errors.swift
│   ├── Energy.swift
│   ├── BackwardEnergy.swift
│   ├── ForwardEnergy.swift
│   ├── DynamicProgramming.swift
│   ├── SeamEditor.swift
│   ├── ResizePlanner.swift
│   ├── BackendSPI.swift
│   ├── CPUBackend.swift
│   └── SeamCarver.swift
├── SeamCarvingAccelerate/
│   ├── AccelerateEnergy.swift
│   └── AccelerateBackend.swift
├── SeamCarvingMetal/
│   ├── MetalContext.swift
│   ├── MetalShaderLibrary.swift
│   ├── MetalResources.swift
│   ├── MetalBackend.swift
│   └── Shaders/SeamCarving.metal
├── SeamCarvingApple/
│   ├── CGImageBridge.swift
│   ├── CIImageBridge.swift
│   ├── CVPixelBufferBridge.swift
│   ├── PlatformImageBridge.swift
│   ├── BackendFactory.swift
│   └── AppleSeamCarver.swift
├── SeamCarvingVision/
│   ├── FaceDetecting.swift
│   ├── VisionFaceDetector.swift
│   ├── FaceRegion.swift
│   ├── FaceMaskRasterizer.swift
│   ├── EnergyComposer.swift
│   └── FaceAwareSeamCarver.swift
├── SeamCarvingCLI/
│   └── CLIOptions.swift
├── seamcarve-cli/CLIEntry.swift
├── SeamCarvingBenchmark/
│   ├── BenchmarkRunner.swift
│   └── BenchmarkReport.swift
└── seamcarve-benchmark/BenchmarkEntry.swift
Tests/
├── SeamCarvingCoreTests/
│   ├── ImageAndMaskTests.swift
│   ├── BackwardEnergyTests.swift
│   ├── DynamicProgrammingTests.swift
│   ├── SeamEditorTests.swift
│   ├── ForwardEnergyTests.swift
│   ├── MaskAndObjectRemovalTests.swift
│   ├── EnlargementTests.swift
│   ├── SeamCarverTests.swift
│   ├── PerformanceTests.swift
│   └── BenchmarkReportTests.swift
├── SeamCarvingAccelerateTests/
│   ├── AccelerateParityTests.swift
│   └── PerformanceTests.swift
├── SeamCarvingMetalTests/
│   ├── MetalKernelTests.swift
│   ├── MetalParityTests.swift
│   └── PerformanceTests.swift
├── SeamCarvingAppleTests/
│   ├── AppleBridgeTests.swift
│   └── BackendSelectionTests.swift
├── SeamCarvingVisionTests/FaceAwareTests.swift
└── SeamCarvingCLITests/
    ├── CLIOptionsTests.swift
    └── CLIEndToEndTests.swift
Benchmarks/README.md
Tests/Fixtures/README.md
Tests/Fixtures/manifest.json
Sources/SeamCarvingCore/SeamCarvingCore.docc/SeamCarving.md
Sources/SeamCarvingApple/SeamCarvingApple.docc/Backends.md
Sources/SeamCarvingVision/SeamCarvingVision.docc/FaceProtection.md
README.md
docs/architecture.md
docs/benchmark-results-template.md
```

## Final Package Graph

Task 1 begins with Core only; later tasks extend the manifest toward this exact final graph without changing dependency direction:

```swift
let package = Package(
    name: "SeamCarvingSwift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
        .library(name: "SeamCarvingAccelerate", targets: ["SeamCarvingAccelerate"]),
        .library(name: "SeamCarvingMetal", targets: ["SeamCarvingMetal"]),
        .library(name: "SeamCarvingApple", targets: ["SeamCarvingApple"]),
        .library(name: "SeamCarvingVision", targets: ["SeamCarvingVision"]),
        .executable(name: "seamcarve-cli", targets: ["seamcarve-cli"]),
        .executable(name: "seamcarve-benchmark", targets: ["seamcarve-benchmark"]),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .target(name: "SeamCarvingAccelerate", dependencies: ["SeamCarvingCore"]),
        .target(
            name: "SeamCarvingMetal",
            dependencies: ["SeamCarvingCore"],
            resources: [.copy("Shaders/SeamCarving.metal")]
        ),
        .target(
            name: "SeamCarvingApple",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal"]
        ),
        .target(
            name: "SeamCarvingVision",
            dependencies: ["SeamCarvingCore", "SeamCarvingApple"],
            linkerSettings: [.linkedFramework("Vision")]
        ),
        .target(name: "SeamCarvingCLI", dependencies: ["SeamCarvingCore"]),
        .executableTarget(
            name: "seamcarve-cli",
            dependencies: ["SeamCarvingCLI", "SeamCarvingApple"]
        ),
        .target(
            name: "SeamCarvingBenchmark",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingApple"]
        ),
        .executableTarget(name: "seamcarve-benchmark", dependencies: ["SeamCarvingBenchmark"]),
        .testTarget(
            name: "SeamCarvingCoreTests",
            dependencies: ["SeamCarvingCore", "SeamCarvingBenchmark"]
        ),
        .testTarget(
            name: "SeamCarvingAccelerateTests",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate"]
        ),
        .testTarget(
            name: "SeamCarvingMetalTests",
            dependencies: ["SeamCarvingCore", "SeamCarvingMetal"]
        ),
        .testTarget(
            name: "SeamCarvingAppleTests",
            dependencies: ["SeamCarvingCore", "SeamCarvingAccelerate", "SeamCarvingMetal", "SeamCarvingApple"]
        ),
        .testTarget(
            name: "SeamCarvingVisionTests",
            dependencies: ["SeamCarvingCore", "SeamCarvingApple", "SeamCarvingVision"]
        ),
        .testTarget(
            name: "SeamCarvingCLITests",
            dependencies: ["SeamCarvingCLI", "SeamCarvingApple"]
        ),
    ]
)
```

Because Swift access control is module-based, Accelerate, Metal, and Apple use `@_spi(Backend) import SeamCarvingCore` for backend conformance/factory injection; the benchmark target imports both `@_spi(Backend)` and `@_spi(Benchmark)` for instrumented timing APIs. Ordinary clients import the library products without SPI. Tests use `@testable import` for their own target and opt into SPI only in tests explicitly exercising backend contracts.

---

### Task 1: Create the Swift Package and Core Value Types

**Files:**
- Create: `Package.swift`
- Create: `Sources/SeamCarvingCore/RGBA8Image.swift`
- Create: `Sources/SeamCarvingCore/Mask.swift`
- Create: `Sources/SeamCarvingCore/Geometry.swift`
- Create: `Sources/SeamCarvingCore/Errors.swift`
- Create: `Tests/SeamCarvingCoreTests/ImageAndMaskTests.swift`

**Interfaces:**
- Produces: `PixelSize`, `RGBA8`, `RGBA8Image`, `Mask`, `SeamOrientation`, `SeamPath`, and `SeamCarvingError`.
- `RGBA8Image.pixels` is row-major straight-alpha RGBA with exactly `width * height * 4` bytes.
- `Mask.values` is row-major with exactly `width * height` finite values inside `0...1`.

- [ ] **Step 1: Write the package manifest and failing value-type tests**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeamCarvingSwift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeamCarvingCore", targets: ["SeamCarvingCore"]),
    ],
    targets: [
        .target(name: "SeamCarvingCore"),
        .testTarget(name: "SeamCarvingCoreTests", dependencies: ["SeamCarvingCore"]),
    ]
)
```

```swift
// Tests/SeamCarvingCoreTests/ImageAndMaskTests.swift
import XCTest
@testable import SeamCarvingCore

final class ImageAndMaskTests: XCTestCase {
    func testImageRejectsWrongByteCount() {
        XCTAssertThrowsError(
            try RGBA8Image(width: 2, height: 2, pixels: [UInt8](repeating: 0, count: 15))
        )
    }

    func testMaskRejectsWrongElementCount() {
        XCTAssertThrowsError(try Mask(width: 2, height: 2, values: [0, 1, 0]))
    }

    func testPixelRoundTrip() throws {
        var image = try RGBA8Image.solid(width: 2, height: 1, color: .init(r: 1, g: 2, b: 3, a: 4))
        image[1, 0] = .init(r: 9, g: 8, b: 7, a: 6)
        XCTAssertEqual(image[1, 0], .init(r: 9, g: 8, b: 7, a: 6))
    }
}
```

In this step, `Package.swift` defines only the `SeamCarvingCore` library product, its target, and its test target. Later tasks extend the manifest only after their source directories exist; the final manifest exposes Core, Accelerate, Metal, Apple, and optional Vision library products plus `seamcarve-cli` and `seamcarve-benchmark` executables listed in the locked structure.

- [ ] **Step 2: Run the tests and confirm the expected compile failure**

Run: `swift test --filter ImageAndMaskTests`

Expected: FAIL because `RGBA8Image`, `RGBA8`, and `Mask` do not exist.

- [ ] **Step 3: Implement the exact core types**

```swift
public struct PixelSize: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) throws
}

public struct RGBA8: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8)
}

public struct SeamPath: Sendable, Equatable {
    public let orientation: SeamOrientation
    public let coordinates: [UInt32]
    public let totalCost: Float
    public init(orientation: SeamOrientation, coordinates: [UInt32], totalCost: Float) throws
}

public enum SeamOrientation: Sendable, Equatable { case vertical, horizontal }

public struct RGBA8Image: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) throws
    public static func solid(width: Int, height: Int, color: RGBA8) throws -> RGBA8Image
    public subscript(_ x: Int, _ y: Int) -> RGBA8 { get set }
}

public struct Mask: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]
    public init(width: Int, height: Int, values: [Float]) throws
    public subscript(_ x: Int, _ y: Int) -> Float { get set }
}

public enum SeamCarvingError: Error, Equatable {
    case invalidDimensions
    case invalidPixelCount(expected: Int, actual: Int)
    case invalidMaskCount(expected: Int, actual: Int)
    case invalidTarget(source: PixelSize, target: PixelSize)
    case invalidSeam
    case noFeasibleSeam
    case invalidConfiguration(String)
    case metalUnavailable
    case metalExecutionFailed(String)
    case unsupportedPixelFormat
    case unsupportedDynamicRange
}
```

Implement checked multiplication for buffer sizes so malicious dimensions cannot overflow. Every initializer above is explicitly `public` because Apple, Accelerate, Metal, Vision, and CLI are separate modules. Seam coordinates and mapped index entries are `UInt32` in every Swift and Metal API; convert to `Int` only after checked bounds validation for Swift array indexing. Parent direction alone is signed `Int8`/Metal `char`. `Mask` rejects non-finite inputs and finite values outside `0...1`; `SeamPath` permits negative finite removal-adjusted costs, but rejects NaN and either infinity. `+infinity` is valid only inside an `EnergyMap` as a blocked pixel, never in a returned feasible seam.

- [ ] **Step 4: Run tests and package validation**

Run: `swift test --filter ImageAndMaskTests && swift package describe >/dev/null`

Expected: PASS with 3 tests and exit code 0.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingCore Tests/SeamCarvingCoreTests/ImageAndMaskTests.swift
git commit -m "feat(core): add package and image primitives"
```

---

### Task 2: Implement Linear Luma and Backward Sobel Energy

**Files:**
- Create: `Sources/SeamCarvingCore/Energy.swift`
- Create: `Sources/SeamCarvingCore/BackwardEnergy.swift`
- Create: `Tests/SeamCarvingCoreTests/BackwardEnergyTests.swift`

**Interfaces:**
- Consumes: `RGBA8Image` from Task 1.
- Produces: `EnergyMap` and `BackwardEnergy.compute(for:) throws -> EnergyMap`.

- [ ] **Step 1: Add hand-calculated failing tests**

```swift
final class BackwardEnergyTests: XCTestCase {
    func testConstantImageHasZeroEnergy() throws {
        let image = try RGBA8Image.solid(width: 3, height: 3, color: .init(r: 128, g: 128, b: 128, a: 255))
        let energy = try BackwardEnergy.compute(for: image)
        XCTAssertEqual(energy.values, [Float](repeating: 0, count: 9))
    }

    func testVerticalStepProducesPositiveCenterEnergy() throws {
        let image = try RGBA8Image.grayscale(width: 3, height: 3, values: [
            0, 0, 255,
            0, 0, 255,
            0, 0, 255,
        ])
        let energy = try BackwardEnergy.compute(for: image)
        XCTAssertEqual(energy[0, 1], 0, accuracy: 0.0001)
        XCTAssertGreaterThan(energy[1, 1], 0)
        XCTAssertGreaterThan(energy[2, 1], 0)
    }
}
```

Add `RGBA8Image.grayscale` only as an internal test helper in the test file, not production API.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter BackwardEnergyTests`

Expected: FAIL because `EnergyMap` and `BackwardEnergy` do not exist.

- [ ] **Step 3: Implement the canonical formula**

Decode each sRGB byte to linear light using the IEC sRGB transfer function, compute luma with `0.2126/0.7152/0.0722`, then apply the standard 3×3 Sobel kernels. Clamp x/y sample coordinates at image edges and store `abs(gx) + abs(gy)` in row-major Float32.

```swift
public struct EnergyMap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]
    public init(width: Int, height: Int, values: [Float]) throws
    public subscript(_ x: Int, _ y: Int) -> Float { values[y * width + x] }
}

public enum EnergyMode: Sendable, Equatable {
    case backwardSobel
    case forwardLuma
}
```

`EnergyMap.init` validates positive dimensions and exact element count, rejects NaN and `-infinity`, and deliberately permits `+infinity` to represent a hard-protected pixel.

- [ ] **Step 4: Run focused and complete core tests**

Run: `swift test --filter BackwardEnergyTests && swift test --filter SeamCarvingCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/Energy.swift Sources/SeamCarvingCore/BackwardEnergy.swift Tests/SeamCarvingCoreTests/BackwardEnergyTests.swift
git commit -m "feat(core): compute deterministic Sobel energy"
```

---

### Task 3: Implement Deterministic Dynamic Programming and Backtracking

**Files:**
- Create: `Sources/SeamCarvingCore/DynamicProgramming.swift`
- Create: `Tests/SeamCarvingCoreTests/DynamicProgrammingTests.swift`

**Interfaces:**
- Consumes: `EnergyMap`.
- Produces: `DynamicProgramming.findVerticalSeam(in:) throws -> SeamPath` and `DynamicProgramming.findSeam(in:orientation:) throws -> SeamPath`. Horizontal search transposes the energy map, calls the same vertical solver, and converts the returned path back to `.horizontal`.

- [ ] **Step 1: Add exact-path failing tests**

```swift
func testFindsKnownVerticalSeam() throws {
    let map = try EnergyMap(width: 3, height: 3, values: [
        1, 3, 0,
        2, 8, 9,
        5, 2, 6,
    ])
    let seam = try DynamicProgramming.findVerticalSeam(in: map)
    XCTAssertEqual(seam.coordinates, [0, 0, 1])
    XCTAssertEqual(seam.totalCost, 5, accuracy: 0.0001)
}

func testEqualCostsChooseSmallestPredecessorX() throws {
    let map = try EnergyMap(width: 3, height: 3, values: [Float](repeating: 1, count: 9))
    XCTAssertEqual(try DynamicProgramming.findVerticalSeam(in: map).coordinates, [0, 0, 0])
}
```

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter DynamicProgrammingTests`

Expected: FAIL because `DynamicProgramming` does not exist.

- [ ] **Step 3: Implement two-row accumulation plus Int8 parents**

For every x, compare predecessor tuples `(cost, predecessorX)` lexicographically. Store `predecessorX - x` as `Int8`. Reject empty maps, NaN, and `-infinity`; allow `+infinity` as an impassable pixel. Backtrack from the smallest x in the last row with minimum finite cumulative cost, or throw `.noFeasibleSeam` when no finite last-row candidate exists.

- [ ] **Step 4: Add and pass validity/property loops**

For deterministic pseudo-random maps of sizes `1...12`, assert coordinate count equals height, each coordinate is in range, neighbor deltas are at most one, and seam cost equals a slow full-matrix oracle included only in the test target. Add a hard-protected full row that throws `.noFeasibleSeam`, a partially protected row that remains solvable, and horizontal-search equivalence against transpose + vertical.

Run: `swift test --filter DynamicProgrammingTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/DynamicProgramming.swift Tests/SeamCarvingCoreTests/DynamicProgrammingTests.swift
git commit -m "feat(core): find deterministic minimum seams"
```

---

### Task 4: Implement Seam Removal, Transpose, and Horizontal Seams

**Files:**
- Create: `Sources/SeamCarvingCore/SeamEditor.swift`
- Create: `Tests/SeamCarvingCoreTests/SeamEditorTests.swift`

**Interfaces:**
- Produces: `SeamEditor.remove(_:from:)`, `SeamEditor.transpose(_:)`, and equivalent mask operations.
- A vertical seam has exactly `image.height` coordinates; a horizontal seam has exactly `image.width` coordinates.

- [ ] **Step 1: Add failing pixel-order tests**

Create a 3×2 image whose red bytes are `[1,2,3,4,5,6]`. Removing vertical seam `[1,1]` must produce red bytes `[1,3,4,6]`. Add invalid length, out-of-range, and discontinuous seam cases.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter SeamEditorTests`

Expected: FAIL because `SeamEditor` does not exist.

- [ ] **Step 3: Implement gather-based removal and transpose**

```swift
public enum SeamEditor {
    public static func remove(_ seam: SeamPath, from image: RGBA8Image) throws -> RGBA8Image
    public static func remove(_ seam: SeamPath, from mask: Mask) throws -> Mask
    public static func transpose(_ image: RGBA8Image) throws -> RGBA8Image
    public static func transpose(_ mask: Mask) throws -> Mask
}
```

Implement horizontal removal as transpose → converted vertical seam → remove → transpose back. Preserve alpha and exact survivor byte order.

- [ ] **Step 4: Verify transpose equivalence**

Add tests that horizontal removal equals manual per-column removal and that double transpose returns the original image and mask.

Run: `swift test --filter SeamEditorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/SeamEditor.swift Tests/SeamCarvingCoreTests/SeamEditorTests.swift
git commit -m "feat(core): remove vertical and horizontal seams"
```

---

### Task 5: Build the CPU Backend and Shrink Planner

**Files:**
- Create: `Sources/SeamCarvingCore/ResizePlanner.swift`
- Create: `Sources/SeamCarvingCore/BackendSPI.swift`
- Create: `Sources/SeamCarvingCore/CPUBackend.swift`
- Create: `Sources/SeamCarvingCore/SeamCarver.swift`
- Create: `Tests/SeamCarvingCoreTests/SeamCarverTests.swift`

**Interfaces:**
- Produces the public async entry point and internal backend abstraction used by all later tasks.

```swift
public enum BackendPreference: Sendable, Equatable { case automatic, cpu, accelerate, metal }
public enum MetalExecutionMode: Sendable, Equatable { case hybrid, full }
public enum DimensionOrder: Sendable, Equatable { case widthThenHeight, heightThenWidth, adaptiveNormalizedCost }

public struct ResizeProgress: Sendable, Equatable {
    public let completedEdits: Int
    public let totalEdits: Int
    public let size: PixelSize
    public init(completedEdits: Int, totalEdits: Int, size: PixelSize)
}

public enum MaskStrength: Sendable, Equatable {
    case soft(Float)
    case hard
}

public struct ProtectionLayer: Sendable, Equatable {
    public let mask: Mask
    public let strength: MaskStrength
    public init(mask: Mask, strength: MaskStrength) throws
}

public struct MaskPair: Sendable {
    public let protectionLayers: [ProtectionLayer]
    public let removal: Mask?
    public let removalWeight: Float

    public init()
    public init(
        protectionLayers: [ProtectionLayer],
        removal: Mask?,
        removalWeight: Float
    ) throws
}

public struct ResizeOptions: Sendable {
    public var energyMode: EnergyMode
    public var dimensionOrder: DimensionOrder
    public var masks: MaskPair
    public var progress: (@Sendable (ResizeProgress) -> Void)?

    public init(
        energyMode: EnergyMode = .backwardSobel,
        dimensionOrder: DimensionOrder = .widthThenHeight,
        masks: MaskPair = .init(),
        progress: (@Sendable (ResizeProgress) -> Void)? = nil
    )
}

@_spi(Backend)
public protocol SeamCarvingBackend: Sendable {
    var identifier: String { get }
    func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath
    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image
}

@_spi(Backend)
public protocol BackwardEnergyProvider: Sendable {
    func compute(for image: RGBA8Image) throws -> EnergyMap
}

@_spi(Backend)
public struct CoreResizeEngine: Sendable {
    public init(backwardEnergyProvider: any BackwardEnergyProvider)
    public func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions
    ) async throws -> SeamPath
    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image
}

public struct CPUBackend: Sendable {
    public init()
}

@_spi(Backend) extension CPUBackend: SeamCarvingBackend {}

public struct SeamCarver: Sendable {
    public init()
    @_spi(Backend) public init(backend: any SeamCarvingBackend)
    public func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions = .init()) async throws -> RGBA8Image
}
```

The zero-argument `MaskPair.init()` creates no protection/removal layers with removal weight 1,000 and is safe for default arguments. The validating initializer and immutable stored properties are the only configured construction path. `ProtectionLayer.init` validates `.soft(weight)` as finite and nonnegative; `MaskPair.init` applies the same validation to every layer and validates removal weight as finite/nonnegative. NaN, either infinity, and negative weights throw `.invalidConfiguration`. `MaskPair` preserves each protection layer independently so a hard face layer never silently upgrades a user's soft layer, and a soft face layer never weakens a user's hard layer.

- [ ] **Step 1: Write failing shrink and validation tests**

Test 4×3 → 2×2, no-op resize, zero target rejection, target larger than source rejection for the shrink-only implementation, progress sequence `[1,2,3]`, and cancellation of a pre-cancelled task.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter SeamCarverTests`

Expected: FAIL because the planner and public API do not exist.

- [ ] **Step 3: Implement exact sequential shrinking**

`CPUBackend` owns `CoreResizeEngine(backwardEnergyProvider: CPUBackwardEnergyProvider())`; this engine is the one reusable orchestration implementation for CPU and Accelerate, not code to duplicate in later modules. It composes backward/forward energy, `DynamicProgramming`, and `SeamEditor`. For horizontal backward search it uses `DynamicProgramming.findSeam(..., .horizontal)`; for horizontal forward search Task 6 supplies the transpose wrapper. The planner uses the selected order; adaptive mode computes both candidate seam costs, divides vertical by height and horizontal by width, and chooses the lower normalized cost with vertical as the tie-break. Call `Task.checkCancellation()` before every seam search and invoke progress only after the edit succeeds.

- [ ] **Step 4: Run all core tests**

Run: `swift test --filter SeamCarvingCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/ResizePlanner.swift Sources/SeamCarvingCore/BackendSPI.swift Sources/SeamCarvingCore/CPUBackend.swift Sources/SeamCarvingCore/SeamCarver.swift Tests/SeamCarvingCoreTests/SeamCarverTests.swift
git commit -m "feat(core): add exact asynchronous shrinking"
```

---

### Task 6: Add Forward-Luma Energy

**Files:**
- Create: `Sources/SeamCarvingCore/ForwardEnergy.swift`
- Create: `Tests/SeamCarvingCoreTests/ForwardEnergyTests.swift`
- Modify: `Sources/SeamCarvingCore/CPUBackend.swift`

**Interfaces:**
- Produces the following exact API; horizontal search is transpose luma + adjustment, vertical recurrence, then coordinate/orientation conversion:

```swift
public struct LuminancePlane: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var values: [Float]
    public init(width: Int, height: Int, values: [Float]) throws
}

public enum ForwardEnergy {
    public static func findVerticalSeam(
        in luminance: LuminancePlane,
        adjustedBaseEnergy: EnergyMap? = nil
    ) throws -> SeamPath

    public static func findSeam(
        in luminance: LuminancePlane,
        orientation: SeamOrientation,
        adjustedBaseEnergy: EnergyMap? = nil
    ) throws -> SeamPath
}
```

- `.forwardLuma` means pure forward disruption cost plus the supplied mask adjustment; it does not silently add Sobel energy.

- [ ] **Step 1: Add failing hand-calculated recurrence tests**

Use a 3×3 grayscale image and a test-local slow implementation of `CU`, `CL`, and `CR`. Assert the chosen path and total cost, plus clamp behavior at x=0 and x=width-1. Assert horizontal results equal transpose + vertical and carry `.horizontal` orientation.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter ForwardEnergyTests`

Expected: FAIL because `ForwardEnergy` does not exist.

- [ ] **Step 3: Implement the recurrence**

Use linear-luma Float32 values. Store two cumulative rows plus Int8 parents. Apply the same lexicographic predecessor tie-break as Task 3. Route `.forwardLuma` through this finder in `CPUBackend`.

- [ ] **Step 4: Verify both energy modes**

Run: `swift test --filter ForwardEnergyTests && swift test --filter SeamCarverTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/ForwardEnergy.swift Sources/SeamCarvingCore/CPUBackend.swift Tests/SeamCarvingCoreTests/ForwardEnergyTests.swift
git commit -m "feat(core): add forward-energy seam search"
```

---

### Task 7: Add Protect/Removal Masks and Object Removal

**Files:**
- Modify: `Sources/SeamCarvingCore/Mask.swift`
- Modify: `Sources/SeamCarvingCore/Energy.swift`
- Modify: `Sources/SeamCarvingCore/CPUBackend.swift`
- Modify: `Sources/SeamCarvingCore/SeamCarver.swift`
- Create: `Tests/SeamCarvingCoreTests/MaskAndObjectRemovalTests.swift`

**Interfaces:**

Task 5 already defines `MaskStrength`, independent `ProtectionLayer` values, and `MaskPair`, so all backends share one configuration type. This task implements their behavior and adds object removal:

```swift
public extension SeamCarver {
    func removeObject(
        from image: RGBA8Image,
        removalMask: Mask,
        restoreOriginalSize: Bool,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image
}
```

- [ ] **Step 1: Add failing mask behavior tests**

Test that a high soft-protect stripe is avoided, a negative removal stripe is selected, hard-protect covering an entire row throws `.noFeasibleSeam`, masks shrink with the image, conflicting hard-protect wins over removal, and mismatched dimensions throw. Add cross-layer tests with one user soft layer plus one independent hard layer and with two soft layers of different weights; assert strengths remain independent after removal/transpose/insertion. Test `.soft(-1)`, `.soft(.nan)`, `.soft(.infinity)`, and invalid removal weights all throw `.invalidConfiguration` through the validating initializers.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter MaskAndObjectRemovalTests`

Expected: FAIL.

- [ ] **Step 3: Implement finite and hard adjustments**

Compose each pixel as `base + sum(softWeight[i] * protectionLayer[i]) - removalWeight * removal`; if any hard layer is nonzero at that pixel, the result is `+infinity` and removal cannot override it. Preserve and transform every layer separately rather than flattening masks. Reject a final row with no finite path. For object removal, compute vertical and horizontal adjusted seams, discard candidates that do not cross a nonzero removal-mask pixel, compare remaining normalized costs, and choose vertical on a tie. Edit image, every protection layer, and the removal mask, and stop only when all removal-mask values are zero; throw `.noFeasibleSeam` if neither orientation crosses the mask.

- [ ] **Step 4: Run mask tests and all core tests**

Run: `swift test --filter MaskAndObjectRemovalTests && swift test --filter SeamCarvingCoreTests`

Expected: PASS except `restoreOriginalSize: true`, which becomes enabled only after Task 8; in this task that option must throw a documented `.invalidTarget` rather than silently ignore restoration.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/Mask.swift Sources/SeamCarvingCore/Energy.swift Sources/SeamCarvingCore/CPUBackend.swift Sources/SeamCarvingCore/SeamCarver.swift Tests/SeamCarvingCoreTests/MaskAndObjectRemovalTests.swift
git commit -m "feat(core): support protection and removal masks"
```

---

### Task 8: Implement Seam Insertion and Enlargement

**Files:**
- Modify: `Sources/SeamCarvingCore/SeamEditor.swift`
- Modify: `Sources/SeamCarvingCore/ResizePlanner.swift`
- Modify: `Sources/SeamCarvingCore/BackendSPI.swift`
- Modify: `Sources/SeamCarvingCore/CPUBackend.swift`
- Modify: `Sources/SeamCarvingCore/SeamCarver.swift`
- Create: `Tests/SeamCarvingCoreTests/EnlargementTests.swift`
- Modify: `Tests/SeamCarvingCoreTests/SeamCarverTests.swift`
- Modify: `Tests/SeamCarvingCoreTests/MaskAndObjectRemovalTests.swift`

**Interfaces:**

```swift
public enum InsertionPolicy: Sendable, Equatable { case neighborAverage }

@_spi(Backend)
public struct MappedSeamSet: Sendable, Equatable {
    public let orientation: SeamOrientation
    public let coordinatesBySeam: [[UInt32]]
    public init(orientation: SeamOrientation, coordinatesBySeam: [[UInt32]]) throws
}

@_spi(Backend)
public extension CoreResizeEngine {
    func discoverMappedSeams(
        count: Int,
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions
    ) async throws -> MappedSeamSet
}

public extension SeamEditor {
    static func insertMappedVerticalSeams(
        _ seams: [[UInt32]],
        into image: RGBA8Image,
        policy: InsertionPolicy
    ) throws -> RGBA8Image

    static func insertMappedVerticalSeams(
        _ seams: [[UInt32]],
        into mask: Mask
    ) throws -> Mask
}
```

- [ ] **Step 1: Add failing insertion and mapping tests**

Test one seam at the right edge, two mapped seams in one row, alpha interpolation, mask interpolation, 1×3 → 3×3 duplication, 3×2 → 5×2 enlargement, 3×2 → 3×4 via transpose, and shrink-then-restore object removal dimensions.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter EnlargementTests`

Expected: FAIL because insertion is absent.

- [ ] **Step 3: Implement exact discovery with an index map**

Multi-seam discovery belongs to `CoreResizeEngine`/backend orchestration because each search must use the selected energy provider and current masks; `SeamEditor` remains a stateless single-edit/insertion utility. On a working copy, initialize each row of `UInt32` `indexMap` to `0..<width`. For every exact discovery iteration, find the seam using the engine, then remove that same seam from the working image, index map, every independent protection layer, and removal mask before the next search. Record original UInt32 coordinates and sort them for each original row. Insert all mapped seams into the original in one gather pass, adding a checked UInt32 offset for prior inserts. Decode neighboring RGB bytes to linear sRGB, average in linear light, encode back to sRGB, and use a rounded arithmetic average for alpha; duplicate the edge pixel when no right neighbor exists. Horizontal discovery/insertion is transpose image, every mask layer, and UInt32 index map → invoke vertical orchestration/edit → transpose back.

- [ ] **Step 4: Enable general resize and object-size restoration**

Route larger targets through insertion. For enlargements greater than the current width/height, operate in batches no larger than `currentDimension - 1`, then repeat on the enlarged image. When the active dimension is one, duplicate that sole row/column once before normal discovery so the batch size cannot become zero. Apply identical mapped insertions to protect/removal masks. Enable `restoreOriginalSize: true` by inserting the same number and orientation of seams removed during object removal.

Run: `swift test --filter EnlargementTests && swift test --filter SeamCarvingCoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingCore/SeamEditor.swift Sources/SeamCarvingCore/ResizePlanner.swift Sources/SeamCarvingCore/BackendSPI.swift Sources/SeamCarvingCore/CPUBackend.swift Sources/SeamCarvingCore/SeamCarver.swift Tests/SeamCarvingCoreTests/EnlargementTests.swift Tests/SeamCarvingCoreTests/SeamCarverTests.swift Tests/SeamCarvingCoreTests/MaskAndObjectRemovalTests.swift
git commit -m "feat(core): support exact seam insertion"
```

---

### Task 9: Add Core Graphics Bridging

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingApple/CGImageBridge.swift`
- Create: `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- Create: `Tests/SeamCarvingAppleTests/AppleBridgeTests.swift`

**Interfaces:**

```swift
public enum CGImageBridge {
    public static func decode(_ image: CGImage) throws -> RGBA8Image
    public static func decode(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> RGBA8Image
    public static func encode(_ image: RGBA8Image) throws -> CGImage
}

public struct AppleSeamCarverConfiguration: Sendable, Equatable {
    public var backend: BackendPreference
    public var metalMode: MetalExecutionMode
    public var deterministic: Bool
    public init(
        backend: BackendPreference = .automatic,
        metalMode: MetalExecutionMode = .full,
        deterministic: Bool = false
    )
}

public struct AppleSeamCarver: Sendable {
    public init(configuration: AppleSeamCarverConfiguration = .init()) throws
    public func resize(
        _ image: CGImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage

    public func findSeam(
        in image: CGImage,
        orientation: SeamOrientation,
        options: ResizeOptions = .init()
    ) async throws -> SeamPath
}
```

At the end of this task, `.cpu`, `.automatic`, and `deterministic` construct the Core backend; requesting `.accelerate` or `.metal` throws `.invalidConfiguration("backend target not wired")` rather than silently selecting CPU. Task 16 replaces this temporary construction branch after all backend targets exist without changing the public signatures.

- [ ] **Step 1: Enable the Apple target and add failing round-trip tests**

Construct `CGImage` fixtures in memory for RGBA, BGRA, grayscale, premultiplied alpha, Display-P3, mirrored/rotated EXIF orientation, and a bitmap with padded bytes-per-row. Assert decoded upright dimensions/pixels and encoded round-trip dimensions. Add 16-bit/extended-range fixtures that must throw `.unsupportedDynamicRange`, rather than clamp or tone map.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter AppleBridgeTests`

Expected: FAIL because the bridge does not exist.

- [ ] **Step 3: Implement explicit rendering into straight RGBA8**

Reject inputs whose component depth exceeds 8 or whose color space is extended range. Render all other inputs through a supported `CGContext` configured with **encoded sRGB**, 8 bits/component, 32 bits/pixel, and premultiplied-last RGBA. Do not assume source provider layout and do not request a straight-alpha bitmap context. Explicitly unpremultiply each rendered pixel into canonical sRGB-encoded straight-alpha RGBA8, defining RGB as zero when alpha is zero. Encoding performs the inverse safe premultiplication into an owned immutable `Data` provider. Test known 50%-alpha and Display-P3 samples numerically so Core's IEC transfer function is applied exactly once.

- [ ] **Step 4: Verify bridge and end-to-end resizing**

Run: `swift test --filter SeamCarvingAppleTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingApple Tests/SeamCarvingAppleTests
git commit -m "feat(apple): bridge CGImage to the core engine"
```

---

### Task 10: Add the Accelerate Energy Backend

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingAccelerate/AccelerateEnergy.swift`
- Create: `Sources/SeamCarvingAccelerate/AccelerateBackend.swift`
- Create: `Tests/SeamCarvingAccelerateTests/AccelerateParityTests.swift`

**Interfaces:**
- `AccelerateEnergyProvider` conforms to Core's backend SPI and `AccelerateBackend` owns the shared `CoreResizeEngine`; it must not copy the resize loop.
- `AccelerateEnergy.compute(for:)` must match `BackwardEnergy.compute(for:)` within `1e-4` per pixel.

```swift
@_spi(Backend) import SeamCarvingCore

public struct AccelerateEnergyProvider: BackwardEnergyProvider, Sendable {
    public init()
    public func compute(for image: RGBA8Image) throws -> EnergyMap
}

public struct AccelerateBackend: Sendable {
    public init()
}

@_spi(Backend) extension AccelerateBackend: SeamCarvingBackend {}
```

- [ ] **Step 1: Enable target and write parity tests**

Generate deterministic constant, gradient, checkerboard, alpha-varied, 1×N, N×1, and 127×65 images. Compare every energy value and final seam against the CPU oracle.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter AccelerateParityTests`

Expected: FAIL because the Accelerate target types do not exist.

- [ ] **Step 3: Implement reusable planar Float buffers**

Use Accelerate for vector luma conversion and Sobel convolution, with preallocated planar Float buffers and explicit edge extension. Preserve the core sRGB-to-linear lookup table and exact coefficients. If a vImage primitive cannot reproduce the core edge/norm semantics, use vDSP for that stage rather than changing the oracle. Construct `CoreResizeEngine(backwardEnergyProvider: AccelerateEnergyProvider())`; forward DP, horizontal transforms, planning, mask editing, cancellation, and progress remain the shared Core implementation.

- [ ] **Step 4: Verify exact paths and tolerance**

Run: `swift test --filter SeamCarvingAccelerateTests && swift test`

Expected: PASS. No seam-path mismatch is permitted on the deterministic fixtures.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingAccelerate Tests/SeamCarvingAccelerateTests
git commit -m "feat(accelerate): add vectorized energy backend"
```

---

### Task 11: Establish Metal Context, Shader Loading, and Test Harness

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingMetal/MetalContext.swift`
- Create: `Sources/SeamCarvingMetal/MetalShaderLibrary.swift`
- Create: `Sources/SeamCarvingMetal/MetalResources.swift`
- Create: `Sources/SeamCarvingMetal/Shaders/SeamCarving.metal`
- Create: `Tests/SeamCarvingMetalTests/MetalKernelTests.swift`

**Interfaces:**

```swift
public actor MetalContext {
    public let device: any MTLDevice
    public static func makeDefault() throws -> MetalContext
    public init(device: any MTLDevice) throws
    public func pipeline(named: String) throws -> any MTLComputePipelineState
    public func submit(_ encode: @Sendable (any MTLCommandBuffer) throws -> Void) async throws
}
```

- [ ] **Step 1: Add the Metal target and a failing passthrough-kernel test**

Bundle `Shaders/SeamCarving.metal` as a copied package resource. The test skips with `XCTSkip` only when `MTLCreateSystemDefaultDevice()` returns nil; otherwise it requires a kernel named `rgbaPassthrough` to copy a 2×2 buffer exactly.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter MetalKernelTests/testPassthrough`

Expected: FAIL because the context and shader are absent.

- [ ] **Step 3: Implement one-time shader compilation and pipeline caching**

Read `Bundle.module/.../SeamCarving.metal`, call `device.makeLibrary(source:options:)` once per process, and cache pipelines by function name inside the actor. This release intentionally uses cached runtime compilation so SwiftPM and tests share one distribution path; document that startup compile time is excluded from steady-state benchmarks. Use `commandBuffer.addCompletedHandler` and `withCheckedThrowingContinuation`, never `waitUntilCompleted()`.

- [ ] **Step 4: Verify success, error propagation, and repeated cache use**

Run: `swift test --filter MetalKernelTests`

Expected: PASS on Metal hardware; only the entire Metal suite may skip on a machine without Metal.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingMetal Tests/SeamCarvingMetalTests/MetalKernelTests.swift
git commit -m "feat(metal): add async compute infrastructure"
```

---

### Task 12: Implement Metal Luma, Sobel, Mask, and Seam Editing Kernels

**Files:**
- Modify: `Sources/SeamCarvingMetal/Shaders/SeamCarving.metal`
- Create: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Modify: `Tests/SeamCarvingMetalTests/MetalKernelTests.swift`
- Create: `Tests/SeamCarvingMetalTests/MetalParityTests.swift`

**Interfaces:**
- `MetalBackend(mode: .hybrid)` computes energy and edits on GPU, but uses core CPU DP/backtracking.
- All active dimensions and strides are explicit kernel parameters; resources may be larger than the active rectangle.
- `SeamCarvingMetal` uses `@_spi(Backend) import SeamCarvingCore`; no ordinary public API exposes the backend protocol existential.

```swift
public struct MetalBackend: Sendable {
    public init(context: MetalContext, mode: MetalExecutionMode = .full)
}

@_spi(Backend) extension MetalBackend: SeamCarvingBackend {}
```

- [ ] **Step 1: Add failing stage-parity tests**

Compare GPU luma, Sobel energy, mask adjustment, vertical removal, mask removal, insertion, RGBA transpose, per-layer mask transpose, and UInt32 index-map transpose against the core oracle on sizes 1×1, 2×3, 17×19, and 65×33. Include dimensions not divisible by threadgroup width.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter MetalKernelTests`

Expected: FAIL because the kernels do not exist.

- [ ] **Step 3: Implement kernels with bounds checks**

Add `rgbaToLinearLuma`, `sobelEnergy`, `applyMasks`, `removeVerticalRGBA`, `removeVerticalMask`, `insertMappedVerticalRGBA`, `insertMappedVerticalMask`, `transposeRGBA`, `transposeMask`, and `transposeUInt32IndexMap`. Use Float32 for luma/energy, signed Int8/Metal `char` only for parent directions (`-1/0/+1`), and UInt32 everywhere for seam/index-map coordinates. Determine threadgroup width from `threadExecutionWidth` and `maxTotalThreadsPerThreadgroup`. Horizontal energy/edit/discovery flows must transpose image, every independent mask layer, and UInt32 index map, reuse the vertical kernels, and transpose results back.

- [ ] **Step 4: Implement hybrid orchestration and parity**

Keep intermediate buffers resident for each operation, read only the Float32 energy map for CPU DP, upload only the resulting UInt32 seam, and perform edit on GPU. Compare final bytes for edit kernels and energy within `1e-4`. Add horizontal parity for image removal/insertion, every protection/removal mask, and UInt32 mapped multi-seam coordinates on non-square inputs; require horizontal output to equal CPU transpose → vertical → transpose.

Run: `swift test --filter SeamCarvingMetalTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingMetal Tests/SeamCarvingMetalTests
git commit -m "feat(metal): accelerate energy and seam editing"
```

---

### Task 13: Implement Full Metal DP, Argmin, and Backtracking

**Files:**
- Modify: `Sources/SeamCarvingMetal/Shaders/SeamCarving.metal`
- Modify: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Modify: `Tests/SeamCarvingMetalTests/MetalParityTests.swift`

**Interfaces:**
- `MetalBackend(mode: .full)` keeps energy, cumulative rows, parents, argmin, seam, and edited image on GPU.
- Full mode supports backward Sobel first; forward energy falls back to hybrid until its dedicated kernel is added within this task's final step.

- [ ] **Step 1: Add failing DP parity tests**

Use hand-authored energy maps, all-equal maps, widths both below and above one threadgroup, non-multiple widths, protect infinity, and deterministic pseudo-random maps. Require exact coordinates and total-cost tolerance `1e-4`.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter MetalParityTests/testFullDPParity`

Expected: FAIL because full DP is absent.

- [ ] **Step 3: Implement row dispatch, reduction, and one-thread backtrack**

Add `initializeDPRow`, `accumulateDPRow`, `reduceFinalRow`, and `backtrackSeam`. Encode `height - 1` dependent row dispatches into a **serial compute pass/encoder** with ping-pong Float32 buffers and a full Int8 parent buffer, using default tracked resources so dispatch order plus hazard tracking establishes visibility. Do not add an unconditional per-row barrier and do not use `threadgroup_barrier` as a grid barrier. If a later implementation chooses untracked resources or concurrent dispatch, it must add `memoryBarrier(resources:)`, fence, or encoder boundaries exactly at the affected read-after-write boundary and add a test that exercises that alternate mode. Argmin compares `(cost, UInt32 x)` so ties choose smaller x.

- [ ] **Step 4: Add forward-luma Metal recurrence**

Add `accumulateForwardDPRow` using the same `CU/CL/CR`, clamp, tie-break, and linear-luma definition as `ForwardEnergy`. Add exact-path parity fixtures for both modes, serial tracked-resource execution, and horizontal transpose flow. Add an all-`+infinity` row fixture that must return `.noFeasibleSeam`, plus injected GPU status/readback failures that must map to `.metalExecutionFailed` rather than returning an invalid seam.

- [ ] **Step 5: Verify full end-to-end parity and commit**

Run: `swift test --filter SeamCarvingMetalTests && swift test`

Expected: PASS with exact seam paths on fixtures and valid near-optimal paths only where floating tolerance makes exact equality impossible.

```bash
git add -- Sources/SeamCarvingMetal/Shaders/SeamCarving.metal Sources/SeamCarvingMetal/MetalBackend.swift Tests/SeamCarvingMetalTests/MetalParityTests.swift
git commit -m "feat(metal): add full GPU seam search"
```

---

### Task 14: Add CIImage and CVPixelBuffer Bridges

**Files:**
- Create: `Sources/SeamCarvingApple/CIImageBridge.swift`
- Create: `Sources/SeamCarvingApple/CVPixelBufferBridge.swift`
- Create: `Sources/SeamCarvingApple/PlatformImageBridge.swift`
- Modify: `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- Modify: `Tests/SeamCarvingAppleTests/AppleBridgeTests.swift`

**Interfaces:**

```swift
public extension AppleSeamCarver {
    func resize(
        _ image: CIImage,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CIImage

    func resize(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CVPixelBuffer

    #if canImport(UIKit)
    func resize(
        _ image: UIImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> UIImage
    #endif

    #if canImport(AppKit)
    func resize(
        _ image: NSImage,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> NSImage
    #endif
}
```

- [ ] **Step 1: Add failing orientation/extent/pixel-format tests**

Test CIImage with non-zero origin, mirrored EXIF orientation, BGRA CVPixelBuffer, padded bytes-per-row, rejection of unsupported planar formats and extended-range/greater-than-8-bit inputs, and an NSImage whose point size differs from its bitmap pixel size. Assert pixel dimensions rather than point dimensions. The final iOS build gate compiles the UIImage branch.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter AppleBridgeTests`

Expected: FAIL because the new overloads do not exist.

- [ ] **Step 3: Implement cached contexts and explicit normalization**

Cache one `CIContext` per Metal device. Apply orientation, normalize extent to origin zero, reject extended-range inputs, and render to **sRGB-encoded** premultiplied RGBA8 before the same explicit unpremultiplication used by `CGImageBridge`; never feed linear-encoded bytes to Core's sRGB decoder. For CVPixelBuffer, accept only documented 8-bit packed `kCVPixelFormatType_32BGRA`/RGBA formats and reject 10-bit, half-float, planar, and extended-range attachments with `.unsupportedDynamicRange` or `.unsupportedPixelFormat`. Use `CVMetalTextureCache` in the Metal path and a locked base-address copy in CPU/Accelerate paths. Retain `CVMetalTexture` until command completion. Normalize `UIImage.imageOrientation` before resizing and preserve `UIImage.scale`; select a concrete `NSBitmapImageRep` for NSImage and never derive pixels from `NSImage.size` points.

- [ ] **Step 4: Verify bridges**

Run: `swift test --filter SeamCarvingAppleTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -- Sources/SeamCarvingApple/CIImageBridge.swift Sources/SeamCarvingApple/CVPixelBufferBridge.swift Sources/SeamCarvingApple/PlatformImageBridge.swift Sources/SeamCarvingApple/AppleSeamCarver.swift Tests/SeamCarvingAppleTests/AppleBridgeTests.swift
git commit -m "feat(apple): bridge CIImage and CVPixelBuffer"
```

---

### Task 15: Add Optional Vision Face Protection Without Polluting Core

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingVision/FaceDetecting.swift`
- Create: `Sources/SeamCarvingVision/VisionFaceDetector.swift`
- Create: `Sources/SeamCarvingVision/FaceRegion.swift`
- Create: `Sources/SeamCarvingVision/FaceMaskRasterizer.swift`
- Create: `Sources/SeamCarvingVision/EnergyComposer.swift`
- Create: `Sources/SeamCarvingVision/FaceAwareSeamCarver.swift`
- Create: `Tests/SeamCarvingVisionTests/FaceAwareTests.swift`

**Dependencies and interfaces:**

Add `.library(name: "SeamCarvingVision", targets: ["SeamCarvingVision"])`. The target depends on `SeamCarvingCore` and `SeamCarvingApple` and links Vision; no Core source file may import Vision. Caire is cited only as a behavior reference for face-aware resizing and object-removal precedence; record the audited Caire tag/commit and license in the Vision DocC page, but do not copy its implementation, fixtures, or API and do not add it as a dependency.

```swift
public struct FaceRegion: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let confidence: Float
    public init(x: Int, y: Int, width: Int, height: Int, confidence: Float) throws
}

public protocol FaceDetecting: Sendable {
    func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion]
}

public struct VisionFaceDetector: FaceDetecting, Sendable {
    public init(revision: Int) throws
    public func detectFaces(inUpright image: CGImage) async throws -> [FaceRegion]
}

public struct CaireInspiredParameters: Sendable, Equatable {
    public var expansionFraction: Float
    public var protectionWeight: Float
    public var minimumConfidence: Float
    public init(
        expansionFraction: Float = 0.10,
        protectionWeight: Float = 1_000,
        minimumConfidence: Float = 0.0
    ) throws
}

public struct VisionQualityParameters: Sendable, Equatable {
    public var expansionFraction: Float
    public var featherFraction: Float
    public var protectionWeight: Float
    public var minimumConfidence: Float
    public init(
        expansionFraction: Float = 0.20,
        featherFraction: Float = 0.30,
        protectionWeight: Float = 1_000,
        minimumConfidence: Float = 0.0
    ) throws
}

public enum FaceProtectionPolicy: Sendable, Equatable {
    case caireInspired(CaireInspiredParameters)
    case visionQuality(VisionQualityParameters)
}

public enum FaceDetectionCadence: Sendable, Equatable {
    case detectOnceAndTransformMask
    case redetectEveryPass
}

public enum FaceMaskRasterizer {
    public static func rasterize(
        regions: [FaceRegion],
        size: PixelSize,
        policy: FaceProtectionPolicy
    ) throws -> Mask
}

public enum EnergyComposer {
    public static func compose(
        userMasks: MaskPair,
        faceMask: Mask,
        policy: FaceProtectionPolicy
    ) throws -> MaskPair
}

public struct FaceAwareSeamCarver: Sendable {
    public init(
        configuration: AppleSeamCarverConfiguration = .init(),
        detector: any FaceDetecting,
        policy: FaceProtectionPolicy,
        cadence: FaceDetectionCadence = .detectOnceAndTransformMask
    ) throws
    public func resize(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        toPixelSize target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> CGImage
}
```

- [ ] **Step 1: Add failing fake-detector and coordinate tests**

Use a fake `FaceDetecting`, not Vision inference, for deterministic unit tests. `FaceAwareSeamCarver` first calls `CGImageBridge.decode(_:orientation:)` and re-encodes the upright canonical image; only that upright image is sent to the detector. Extract normalized-bottom-left to upright-origin-top-left conversion into an internal pure helper and test it with `@testable import SeamCarvingVision`; unit tests do not run real Vision inference. Because `FaceRegion.init` has no image size, it validates only `x/y >= 0`, positive width/height, overflow-safe `x + width`/`y + height`, and confidence finite within `0...1`. Relative image-bound handling belongs to `FaceMaskRasterizer.rasterize(regions:size:policy:)`: intersect partially crossing regions with `PixelSize`, but reject a wholly out-of-bounds region with `.invalidConfiguration`; test every clipped edge and wholly outside input. `VisionFaceDetector.init` validates `revision` against `VNDetectFaceRectanglesRequest.supportedRevisions`, stores it, and assigns `request.revision` for every request; unsupported values throw `.invalidConfiguration`. Never use an implicit latest/default revision.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter FaceAwareTests`

Expected: FAIL because the Vision target and pipeline types do not exist.

- [ ] **Step 3: Implement the fixed pipeline and policies**

Implement only `FaceDetecting -> FaceRegion -> FaceMaskRasterizer -> EnergyComposer`. Both parameter initializers validate `minimumConfidence` as finite within `0...1`; the explicit v1 default is `0.0`, pending golden-corpus calibration. `FaceMaskRasterizer` filters out regions whose confidence is strictly less than the selected policy's threshold before expansion or clipping; confidence exactly equal to the threshold is included. `.caireInspired(parameters)` is explicitly **not Caire-compatible**: it is a configurable rectangular mask inspired by Caire's face-aware behavior, using the validated expansion and finite soft weight; no claim is made about Caire's blur, calibration, or numerical output. `.visionQuality(parameters)` uses validated expansion/feather/weight and rasterizes a feathered ellipse. `EnergyComposer` appends the face mask as a new `ProtectionLayer` without merging it into user layers, preserving every layer's independent hard/soft strength. It zeros removal-mask values wherever the face mask is nonzero, so face protection overrides removal without hardening a user soft mask or weakening a user hard mask.

`FaceAwareSeamCarver.resize` defines `ResizeOptions.masks` in the original `CGImage` raster coordinate system. Before detection or resizing, validate every protection/removal layer against the original raster dimensions, then rotate/mirror each mask with the exact same `CGImagePropertyOrientation` transform applied to the image so all data enters upright canonical coordinates together; reject mismatches before invoking Vision. The default `.detectOnceAndTransformMask` detects once on that upright canonical image, passes the composed mask into Core, and relies on the exact seam editor to transform it after each edit. `.redetectEveryPass` works on canonical `RGBA8Image` plus current user masks: call `AppleSeamCarver.findSeam`, apply that exact returned path with `SeamEditor` to both image and masks, re-encode the current upright image, rerun the same explicit Vision revision, and recompose before the next pass. For insertion, discover exactly one mapped seam and apply it to image and masks before redetection. Respect `DimensionOrder`; adaptive mode queries both candidate seams and uses the same normalized-cost/vertical-tie rule as `ResizePlanner`. Thus no hidden second seam search can choose a different path, and user masks remain coordinate-aligned. Preserve cancellation/progress semantics and never run Vision from Core.

- [ ] **Step 4: Verify cadence, precedence, and package boundaries**

Test detector call count (one versus number of edit passes), face-over-removal precedence, both raster policies with non-default validated parameters, mirrored/rotated input, clipped edge faces, empty detections, and cancellation. For each policy test confidence just below, exactly equal to, and just above `minimumConfidence`, plus NaN/negative/>1 threshold rejection. Use asymmetric user protection/removal masks with rotated and mirrored images to assert the same orientation transform keeps image pixels, face regions, and every user-mask layer aligned; mismatched original-raster mask dimensions must fail before detector invocation. Add a user hard layer + soft face layer case and a user soft layer + face layer case; assert layer count, masks, and strengths survive composition and each seam transform unchanged except for coordinates. Revision remains solely a `VisionFaceDetector` concern and cadence solely a `FaceAwareSeamCarver` concern. Also run:

```bash
swift test --filter SeamCarvingVisionTests
! grep -R "import Vision" Sources/SeamCarvingCore
swift test
```

Expected: all tests PASS and grep finds no Vision import in Core.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingVision Tests/SeamCarvingVisionTests
git commit -m "feat(vision): add optional face protection pipeline"
```

---

### Task 16: Wire Backend Selection, Fallback, Cancellation, and Progress

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/SeamCarvingCore/SeamCarver.swift`
- Modify: `Sources/SeamCarvingAccelerate/AccelerateBackend.swift`
- Modify: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Create: `Sources/SeamCarvingApple/BackendFactory.swift`
- Modify: `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- Modify: `Tests/SeamCarvingCoreTests/SeamCarverTests.swift`
- Modify: `Tests/SeamCarvingMetalTests/MetalParityTests.swift`
- Modify: `Tests/SeamCarvingAppleTests/AppleBridgeTests.swift`
- Create: `Tests/SeamCarvingAppleTests/BackendSelectionTests.swift`

**Interfaces:**
- Explicit `.cpu`, `.accelerate`, and `.metal` never silently change backend.
- `.automatic` chooses Accelerate for this first release, with CPU as its only fallback. Metal remains explicit opt-in until real-device benchmark reports justify a policy change.
- Explicit `.metal` never silently falls back; allocation or execution failures surface to the caller.

This task implements the final `AppleSeamCarverConfiguration` and throwing initializer already declared in Task 9. `deterministic: true` always selects CPU and is documented as overriding `backend`.

- [ ] **Step 1: Write failing selector/fallback tests with fake backends**

Inject fake availability, Accelerate construction failure, Metal execution failure, cancellation, and progress recording. Assert automatic fallback is limited to Accelerate → CPU and explicit backend errors are not swallowed.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter BackendSelectionTests`

Expected: FAIL on selector behavior.

- [ ] **Step 3: Implement an internal injectable selector**

Update `Package.swift` so `SeamCarvingApple` depends on `SeamCarvingCore`, `SeamCarvingAccelerate`, and `SeamCarvingMetal`; the latter two depend only on Core, so the graph remains acyclic. `SeamCarvingApple` uses `@_spi(Backend) import SeamCarvingCore`. Keep selection in an internal injectable `BackendFactory` owned by `SeamCarvingApple`, because the core module cannot depend on Accelerate or Metal modules. Put fake-factory selector tests in `SeamCarvingAppleTests/BackendSelectionTests.swift`, whose test target depends on all four modules. Make each resize request own its mutable image/masks/scratch state. Check cancellation before scheduling GPU work and after every completed command buffer. Ensure progress is monotonic and never emitted for a failed edit.

- [ ] **Step 4: Run concurrency stress tests**

Launch 16 independent synthetic resizes in a throwing task group, cancel half after their first progress event, and assert the remaining outputs and cancelled errors. Run under Thread Sanitizer once:

Run:

```bash
swift test
PACKAGE_SCHEME="$(xcodebuild -list -json | python3 -c 'import json,sys; d=json.load(sys.stdin); root=next(v for v in d.values() if isinstance(v,dict) and "schemes" in v); print(next(x for x in root["schemes"] if x.endswith("-Package")))')"
xcodebuild -scheme "$PACKAGE_SCHEME" -destination 'platform=macOS' -enableThreadSanitizer YES test
```

Expected: the package scheme is discovered rather than guessed, all ordinary tests PASS, and Thread Sanitizer reports no data races.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingCore/SeamCarver.swift Sources/SeamCarvingAccelerate/AccelerateBackend.swift Sources/SeamCarvingMetal/MetalBackend.swift Sources/SeamCarvingApple/BackendFactory.swift Sources/SeamCarvingApple/AppleSeamCarver.swift Tests/SeamCarvingCoreTests/SeamCarverTests.swift Tests/SeamCarvingMetalTests/MetalParityTests.swift Tests/SeamCarvingAppleTests/AppleBridgeTests.swift Tests/SeamCarvingAppleTests/BackendSelectionTests.swift
git commit -m "feat: select backends and support cancellation"
```

---

### Task 17: Add the macOS CLI and Golden-Corpus Workflow

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SeamCarvingCLI/CLIOptions.swift`
- Create: `Sources/seamcarve-cli/CLIEntry.swift`
- Create: `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- Create: `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`
- Create: `Tests/Fixtures/README.md`
- Create: `Tests/Fixtures/manifest.json`

**Interfaces:**
- CLI syntax: `seamcarve-cli INPUT OUTPUT --width PIXELS --height PIXELS --backend automatic|cpu|accelerate|metal --energy backward|forward`.
- Width and height are target pixel dimensions, never deletion counts.
- CLI execution and process-spawning integration tests are macOS-only. The `SeamCarvingCLI` parser target remains platform-neutral so `CLIOptionsTests` compiles and runs in the iOS aggregate gate.
- `Sources/seamcarve-cli/CLIEntry.swift` uses a non-special filename and declares exactly one async `@main` entry type in each conditional-compilation branch, avoiding Swift's top-level-code/`@main` conflict.

- [ ] **Step 1: Add a failing CLI smoke test to the executable target**

Put argument parsing in the internal `SeamCarvingCLI` target as `CLIOptions.parse(_:)`; test missing paths, invalid dimensions, unknown backend, and the documented example from `SeamCarvingCLITests`.

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter CLIOptionsTests`

Expected: FAIL because CLI parsing is absent.

- [ ] **Step 3: Implement Foundation-only parsing and ImageIO I/O**

Decode with `CGImageSource`, call `AppleSeamCarver`, and encode PNG/JPEG based on output extension using `CGImageDestination`. Print per-edit progress to stderr and final dimensions/backend to stdout. Exit 64 for arguments, 65 for decode/encode, 70 for processing failure, and 130 for cancellation. Keep all executable-only implementation under `#if os(macOS)`; its entry declaration is `@main enum CLIEntry` with `static func main() async`, so it can await carving without top-level code. `Sources/seamcarve-cli/CLIEntry.swift` must also contain a compile-safe `#else` `@main` implementation for non-macOS targets that does not reference `Process`, AppKit, or macOS-only APIs and reports the executable as unavailable without invoking the carving pipeline:

```swift
#if os(macOS)
// macOS ImageIO CLI @main implementation
#else
import Foundation

@main
enum UnsupportedCLIPlatform {
    static func main() async {
        FileHandle.standardError.write(
            Data("seamcarve-cli is available only on macOS\n".utf8)
        )
    }
}
#endif
```

- [ ] **Step 4: Run an end-to-end generated-image smoke test**

In `CLIEndToEndTests`, generate a 32×24 PNG using Core Graphics. Locate the executable through an environment variable `SEAMCARVE_CLI_PATH`, spawn it with `Process`, produce 20×18, reopen the result, and assert dimensions and exit status. `Foundation.Process` is referenced only inside `#if os(macOS)`. On non-macOS, compile a separate test class whose sole test throws `XCTSkip("seamcarve-cli process test is macOS-only")`; that branch must not mention `Process` even in a property or helper signature:

The file starts with `#if os(macOS)` before importing Foundation or declaring the real `CLIEndToEndTests`; that entire branch contains fixture generation and every `Process` reference. Its non-macOS branch is exactly:

```swift
#else
import XCTest

final class CLIEndToEndTests: XCTestCase {
    func testMacOSOnly() throws {
        throw XCTSkip("seamcarve-cli process test is macOS-only")
    }
}
#endif
```

The macOS branch additionally throws `XCTSkip` when `SEAMCARVE_CLI_PATH` is absent so ordinary unit-test runs stay usable; the required macOS release gate below always supplies it. `CLIOptionsTests` has no platform guard and remains part of iOS simulator testing.

Run:

```bash
swift test --filter CLIOptionsTests
swift build --product seamcarve-cli
SEAMCARVE_CLI_PATH="$(swift build --show-bin-path)/seamcarve-cli" swift test --filter CLIEndToEndTests
swift run seamcarve-cli --help
```

Expected: on macOS, parser and Process-based E2E tests PASS and help exits 0. In the iOS aggregate gate, `CLIOptionsTests` PASS, `CLIEndToEndTests.testMacOSOnly` reports SKIP, and the executable's controlled unavailable branch compiles without referencing `Process`.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingCLI Sources/seamcarve-cli Tests/SeamCarvingCLITests Tests/Fixtures
git commit -m "feat(cli): add seam carving command line tool"
```

---

### Task 18: Add Repeatable Performance Benchmarks

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/SeamCarvingCore/BackendSPI.swift`
- Modify: `Sources/SeamCarvingCore/CPUBackend.swift`
- Modify: `Sources/SeamCarvingAccelerate/AccelerateBackend.swift`
- Modify: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Create: `Sources/SeamCarvingBenchmark/BenchmarkRunner.swift`
- Create: `Sources/SeamCarvingBenchmark/BenchmarkReport.swift`
- Create: `Sources/seamcarve-benchmark/BenchmarkEntry.swift`
- Create: `Tests/SeamCarvingCoreTests/PerformanceTests.swift`
- Create: `Tests/SeamCarvingAccelerateTests/PerformanceTests.swift`
- Create: `Tests/SeamCarvingMetalTests/PerformanceTests.swift`
- Create: `Tests/SeamCarvingCoreTests/BenchmarkReportTests.swift`
- Create: `Benchmarks/README.md`

**Interfaces:**
- Add an internal `SeamCarvingBenchmark` library target depending on Core, Accelerate, Metal, and Apple; add an executable product/target `seamcarve-benchmark` depending only on that library; make `SeamCarvingCoreTests` depend on the benchmark library for `BenchmarkReportTests`. These edges all point toward already-built libraries and introduce no cycle. `Sources/seamcarve-benchmark/BenchmarkEntry.swift` uses a non-special filename and declares a single `@main` entry with `static func main() async throws`, avoiding top-level-code/`@main` conflicts while awaiting GPU work. The executable emits versioned JSON, not human-only XCTest output.
- Add an SPI `InstrumentedSeamCarvingBackend.benchmarkResize(...)` returning per-iteration phase nanoseconds for energy, mask, DP, argmin/backtrack, edit, command encoding, GPU wait, end-to-end, and peak scratch bytes. `BenchmarkRunner` separately times Apple decode/encode bridges and writes `bridgeNS`; CPU/Accelerate report zero for GPU-only fields rather than omitting them.
- Fixtures are generated deterministically at runtime; no copyrighted photos enter the repository.

```swift
@_spi(Benchmark)
public struct BackendPhaseDurations: Sendable, Codable, Equatable {
    public var bridgeNS: UInt64
    public var energyNS: UInt64
    public var maskNS: UInt64
    public var dynamicProgrammingNS: UInt64
    public var backtrackNS: UInt64
    public var editNS: UInt64
    public var commandEncodingNS: UInt64
    public var gpuWaitNS: UInt64
    public var totalNS: UInt64
    public var peakScratchBytes: UInt64
    public init(
        bridgeNS: UInt64,
        energyNS: UInt64,
        maskNS: UInt64,
        dynamicProgrammingNS: UInt64,
        backtrackNS: UInt64,
        editNS: UInt64,
        commandEncodingNS: UInt64,
        gpuWaitNS: UInt64,
        totalNS: UInt64,
        peakScratchBytes: UInt64
    )
}

@_spi(Benchmark)
public protocol InstrumentedSeamCarvingBackend: SeamCarvingBackend {
    func benchmarkResize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> (RGBA8Image, BackendPhaseDurations)
}
```

- [ ] **Step 1: Add benchmark fixture generation and signposts**

Generate 256², 1920×1080, 3840×2160, 2048×512, and 512×2048 images using seeded gradients/noise and synthetic protected regions. The runner accepts `--sizes`, `--seams`, `--energies`, `--backends`, `--warmup`, `--iterations`, and `--output`. For each bucket, discard warmups, retain every raw iteration, sort values, compute p50 by nearest-rank `ceil(0.50*n)-1` and p95 by `ceil(0.95*n)-1`, and encode hardware/OS/Swift/backend/configuration plus raw samples and phase summaries. `BenchmarkReportTests` locks percentile math and JSON schema version `1`.

- [ ] **Step 2: Verify benchmarks execute in Release configuration**

Run:

```bash
swift test -c release --filter BenchmarkReportTests
swift test -c release --filter PerformanceTests
swift run -c release seamcarve-benchmark --sizes 256x256 --seams 1,8 --energies backward,forward --backends cpu,accelerate --warmup 1 --iterations 5 --output /tmp/seam-carving-benchmark.json
python3 -c 'import json; d=json.load(open("/tmp/seam-carving-benchmark.json")); phases={"bridge","energy","mask","dynamicProgramming","backtrack","edit","commandEncoding","gpuWait","total"}; assert d["schemaVersion"] == 1; assert d["results"]; assert all(phases == set(r["phaseSummaries"]) and all({"p50NS","p95NS","rawNS"} <= set(v) and len(v["rawNS"]) == 5 for v in r["phaseSummaries"].values()) and "peakScratchBytes" in r for r in d["results"])'
```

Expected: PASS; JSON contains raw samples, actual p50/p95 for every phase, and peak scratch bytes. Backend parity is checked before any timing sample is accepted.

- [ ] **Step 3: Document the benchmark matrix and automatic-policy rule**

`Benchmarks/README.md` records warm-up requirements, command lines, whether shader compilation/decode is included, the fixed nearest-rank p50/p95 procedure, real-device requirement, and the exact rule for changing `.automatic`: both iPhone and Apple-silicon Mac must show Metal at least 15% lower p50 than Accelerate without worsening p95 peak scratch by more than 10% for the affected request-size bucket.

- [ ] **Step 4: Capture a local baseline without changing policy constants**

Run: `swift run -c release seamcarve-benchmark --sizes 256x256,1920x1080,3840x2160,2048x512,512x2048 --seams 1,8,32,10%,25% --energies backward,forward --backends cpu,accelerate,metal-hybrid,metal-full --warmup 3 --iterations 10 --output /tmp/seam-carving-benchmark.json`

Expected: exit 0. Attach `/tmp/seam-carving-benchmark.json` to the execution report; do not commit machine-specific numbers. On a host without Metal, rerun the local smoke subset without Metal, but the physical-device release gate still requires Metal rows.

- [ ] **Step 5: Commit**

```bash
git add -- Package.swift Sources/SeamCarvingCore/BackendSPI.swift Sources/SeamCarvingCore/CPUBackend.swift Sources/SeamCarvingAccelerate/AccelerateBackend.swift Sources/SeamCarvingMetal/MetalBackend.swift Sources/SeamCarvingBenchmark Sources/seamcarve-benchmark Benchmarks Tests/SeamCarvingCoreTests/PerformanceTests.swift Tests/SeamCarvingCoreTests/BenchmarkReportTests.swift Tests/SeamCarvingAccelerateTests/PerformanceTests.swift Tests/SeamCarvingMetalTests/PerformanceTests.swift
git commit -m "test: benchmark seam carving backends"
```

---

### Task 19: Documentation, Platform Builds, and Release Gate

**Files:**
- Create: `README.md`
- Create: `docs/architecture.md`
- Create: `docs/benchmark-results-template.md`
- Create: `Sources/SeamCarvingCore/SeamCarvingCore.docc/SeamCarving.md`
- Create: `Sources/SeamCarvingApple/SeamCarvingApple.docc/Backends.md`
- Create: `Sources/SeamCarvingVision/SeamCarvingVision.docc/FaceProtection.md`

**Interfaces:**
- README documents only shipped behavior and current limitations.
- `docs/architecture.md` records the locked energy/mask/tie-break/color semantics required for future backend parity.

- [ ] **Step 1: Write user-facing examples and limitations**

Include Swift examples for `RGBA8Image`, `CGImage`, async cancellation, progress, masks, enlargement, explicit backends, CIImage, CVPixelBuffer, and optional Vision face protection with an explicit request revision. Document `.caireInspired` as non-equivalent inspiration versus `.visionQuality`, both detection cadences, upright coordinates, independent protection-layer strengths, and face-over-removal precedence. State that video coherence, HDR/extended-range input, learned saliency, MLX, Core ML, approximate batches, transport maps, and Lanczos/conventional pre-scaling are not shipped. Exact seam semantics remain the default; any future pre-scale feature must be an explicit opt-in. DocC must document every public initializer and the backend SPI as unsupported for ordinary clients.

- [ ] **Step 2: Run documentation and formatting sanity checks**

Run:

```bash
git diff --check
swift package describe
swift test
swift test -c release
PACKAGE_SCHEME="$(xcodebuild -list -json | python3 -c 'import json,sys; d=json.load(sys.stdin); root=next(v for v in d.values() if isinstance(v,dict) and "schemes" in v); print(next(x for x in root["schemes"] if x.endswith("-Package")))')"
xcodebuild docbuild -scheme "$PACKAGE_SCHEME" -destination 'platform=macOS'
```

Expected: all commands exit 0.

- [ ] **Step 3: Verify macOS and iOS builds**

Discover the generated aggregate package scheme and use it for both builds rather than guessing a module scheme:

```bash
PACKAGE_SCHEME="$(xcodebuild -list -json | python3 -c 'import json,sys; d=json.load(sys.stdin); root=next(v for v in d.values() if isinstance(v,dict) and "schemes" in v); print(next(x for x in root["schemes"] if x.endswith("-Package")))')"
xcodebuild -scheme "$PACKAGE_SCHEME" -destination 'platform=macOS' build
xcodebuild -scheme "$PACKAGE_SCHEME" -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: scheme discovery and both builds succeed.

- [ ] **Step 4: Run executable simulator/Metal gates and record the external device gate**

Run these exact automated gates:

```bash
PACKAGE_SCHEME="$(xcodebuild -list -json | python3 -c 'import json,sys; d=json.load(sys.stdin); root=next(v for v in d.values() if isinstance(v,dict) and "schemes" in v); print(next(x for x in root["schemes"] if x.endswith("-Package")))')"
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 xcodebuild -scheme "$PACKAGE_SCHEME" -destination 'platform=macOS' test
SIM_UDID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for devices in d["devices"].values() for x in devices if x["name"].startswith("iPhone") and x.get("isAvailable",False)))')"
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 xcodebuild -scheme "$PACKAGE_SCHEME" -destination "platform=iOS Simulator,id=$SIM_UDID" CODE_SIGNING_ALLOWED=NO test
swift build --product seamcarve-cli
SEAMCARVE_CLI_PATH="$(swift build --show-bin-path)/seamcarve-cli" swift test --filter CLIEndToEndTests
```

A physical iPhone/iPad Metal parity run, GPU validation capture, energy measurement, and the Release benchmark matrix are an explicitly **manual external release gate**, not something this repository-only agent may claim to have executed. Populate `docs/benchmark-results-template.md` with device model/UDID suffix, OS/Xcode/Swift versions, git commit, Vision revision, backend/mode, benchmark JSON attachment, p50/p95 per phase, peak scratch, Metal validation screenshot/log, date, and operator. If evidence is unavailable, mark the release gate pending rather than passing it. Acceptance criteria:

- zero test failures;
- zero Metal validation errors;
- zero Thread Sanitizer findings;
- exact CPU/Accelerate seam parity on deterministic fixtures;
- Metal seam legality and total cost within `1e-4` of CPU fixtures;
- measured peak scratch stays within the documented allocation budget derived from live buffers: CPU two Float32 DP rows + Int8 parent map + Float32 luma/energy + temporary UInt32 insertion index map; Metal two Float32 DP rows + Int8 parent + UInt32 seam/index map + declared luma/energy/mask resources. Any extra full-frame allocation must be named and justified in `docs/architecture.md`;
- no main-thread blocking waits.

- [ ] **Step 5: Commit the final documentation**

```bash
git add -- README.md Sources/SeamCarvingCore/SeamCarvingCore.docc Sources/SeamCarvingApple/SeamCarvingApple.docc Sources/SeamCarvingVision/SeamCarvingVision.docc docs/architecture.md docs/benchmark-results-template.md
git commit -m "docs: document Swift seam carving package"
```

---

## Final Execution Checklist

- [ ] Every task has its own commit and review gate.
- [ ] `git status --short` contains no unrelated changes.
- [ ] `git diff --check` passes.
- [ ] Debug and Release test suites pass.
- [ ] macOS and generic iOS builds pass.
- [ ] Metal tests either pass on supported hardware or explicitly skip only because no Metal device exists.
- [ ] Metal API Validation and Thread Sanitizer report no issues.
- [ ] The benchmark execution report records hardware, OS, Xcode, Swift, backend, image dimensions, seam count, p50/p95, and peak memory.
- [ ] `grep -R "import Vision" Sources/SeamCarvingCore` returns no matches; Vision tests record the explicit face-request revision and both cadence call counts.
- [ ] Publication remains marked pending until the project owner selects and adds a license; this implementation plan does not create one.
- [ ] A separate reviewer checks spec compliance and public API consistency before merge.

## Handoff Prompt for the New Agent

Copy the following prompt into the new agent session:

```text
Implement docs/superpowers/plans/2026-08-21-seam-carving-swift-implementation.md from this repository.

First read docs/ios-macos-seam-carving-implementation-research.md and the full implementation plan. Use superpowers:using-git-worktrees, then use superpowers:executing-plans so one agent executes tasks strictly in order. Run every listed TDD verification command, create only the scoped commits, and stop at any failed verification instead of claiming completion. Do not add MLX, Core ML, video coherence, HDR support, transport maps, or approximate batch seams. Vision is allowed only in the optional SeamCarvingVision target and Core must remain Vision-free. Preserve unrelated worktree changes and report the exact test/build/benchmark evidence at the end.
```
