# Capability Matrix — Caire Alignment

This document freezes the public, user-facing capability contract for
SeamCarvingSwift and classifies each Caire-inspired capability. It is the
baseline for GUI work.

Classification legend:

- **existing** — already implemented and reachable through public APIs.
- **requires API exposure** — implemented in Core/Apple but needs GUI wiring.
- **requires new implementation** — not yet present; deferred to a later task.

| # | Capability | Owner | Acceptance criterion | Status |
|---|-----------|-------|----------------------|--------|
| 1 | Shrink and enlarge in both dimensions | Core/Apple | Output reaches requested pixel dimensions | existing |
| 2 | Backward and forward energy | Core | Existing parity tests remain green | existing |
| 3 | Protect and remove masks | Core/UI/CLI | Painted or loaded masks affect seam selection and remain aligned after edits | verified; Core, CLI, simulator, and iPad App XCTest pass |
| 4 | Object removal and optional restoration | Core/UI | Removal mask can be applied and original dimension restored | verified; Core and GUI workflow tests pass |
| 5 | Face-aware protection | Vision/UI/CLI | Vision face regions become editable protection policy with explicit cadence | verified; fake-detector GUI tests and platform XCTest pass; real face-image smoke test recommended |
| 6 | Caire-style large resize optimization | Planner/UI/CLI | Explicit opt-in pre-scale mode, never implicit in exact mode | implemented |
| 7 | CPU/Accelerate/Metal selection | Apple/UI/CLI | Backend and deterministic mode are visible and explainable | verified; iPad Metal screening passed 16/16 |
| 8 | Progress, cancellation, and preview | Core/UI | User can cancel an active resize and retain the source document | implemented |
| 9 | Image import/export | Platform UI | macOS file URLs, iPhone/iPad Photos/files, and PNG/JPEG export work | verified by host/platform XCTest; manual picker smoke test recommended |
| 10 | Shared Apple experience | App | Same feature model works on macOS, iPhone, and iPad with adaptive layouts | verified; macOS/iOS/iPadOS tests and iPad device run pass |
| 11 | Scalar resize modes (percentage, square) | CLI/Core | `--percentage P` scales from source with round-half-up and min 1; `--square` targets the shorter side; conflicts with explicit dimensions are rejected | verified; Core and CLI tests pass |
| 12 | Configurable energy controls (blur radius, Sobel threshold) | Core/Apple/CLI | Blur and threshold reach actual backward Sobel energy; zero equals default; CPU and Accelerate match; Metal falls back to CPU | verified; Core, Accelerate, and Metal parity tests pass |
| 13 | Recursive bounded CLI batch processing | CLI | Recursive image enumeration, normalized ordering, bounded concurrency, partial-failure summary | verified; batch tests pass |
| 14 | Seam debug artifacts | Core/CLI | Actual seam observations produce manifest and overlay sidecars with explicit coordinates/color/shape | verified; seam/debug tests pass; Metal debug explicitly falls back to CPU |
| 15 | Typed CLI argument parsing | CLI | `swift-argument-parser` handles syntax while domain validation remains in CLI configuration | verified; parser regression and full package tests pass |
| 16 | Capability-based platform modules | Core/Apple adapters | Core has no Apple-framework dependency; image-object bridges are separate Runtime/Imaging/CoreVideo/UIKit/AppKit products | verified by the Core-only macOS/Linux/Windows build gate and target separation; this does not claim full Windows/Linux application support |
| 17 | Experimental browser WASM demo | Isolated WASM bridge / Canvas | Local PNG/JPEG browser workflow resizes RGBA8 pixels in a Worker and exports PNG without network upload | experimental; static-host browser E2E and manual Safari/Edge checklist are required; this is not general WASM, image-I/O, CLI, or app support |

## Face protection is a capability choice, not Pigo compatibility

Caire-inspired face protection (`.caireInspired` Vision mode) is a *capability
choice* within the Vision adapter. It is **not** a claim of compatibility with
Pigo or any other detector. The package uses Apple Vision as the detection
backend; `.caireInspired` only mirrors Caire's policy shape (protect face
rectangles, explicit cadence via `.detectOnce` / `.redetectEachPass`).

## API gap analysis before GUI work

The GUI must be able to construct controls for energy mode, dimension order,
masks, and progress. Verification against `Sources/SeamCarvingCore/ResizePlanner.swift`:

- `ResizeOptions` exposes `energyMode: EnergyMode`, `dimensionOrder: DimensionOrder`,
  `masks: MaskPair`, and `progress: (@Sendable (ResizeProgress) -> Void)?`.
- `AppleSeamCarver.resize(_:toPixelSize:options:)` accepts `ResizeOptions` and
  forwards it to the backend.

**Conclusion: no GUI-blocking API gap was found.** All GUI-relevant controls
(energy mode, dimension order, masks, progress callback) are already expressible
through the public `ResizeOptions` + progress field. No new library APIs are
added in this task — the Caire-style pre-scale API is scheduled for Task 2.

## Platform scope

The v2 `SeamCarvingApple` compatibility facade re-exports Runtime and Imaging
for CGImage users only. UIKit and AppKit callers import their corresponding
capability products explicitly. The Core cross-host CI gate validates only
`SeamCarvingCore`; it is not a declaration that Windows or Linux image I/O, UI,
or CLI support has shipped. The isolated [experimental browser WASM demo](../Examples/WasmDemo/README.md)
executes the CPU Core path locally in a Worker, but does not imply general WASM
platform, image-I/O, CLI, or application support. Android remains an
architecture-ready adapter boundary, not a supported platform.

The current CLI uses Apple ImageIO/CoreGraphics codecs. Future cross-host work
will split its model/pipeline layer into `SeamCarvingCLIModel` and the Apple
codec layer into `SeamCarvingAppleCLIImageIO`; that boundary is documentation
only in v2.
