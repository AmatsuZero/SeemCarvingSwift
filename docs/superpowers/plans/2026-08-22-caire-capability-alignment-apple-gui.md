# Caire Capability Alignment and Apple GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the library's user-visible image-resizing capabilities with Caire's core feature set and deliver one shared SwiftUI product experience for macOS, iPhone, and iPad.

**Architecture:** Keep `SeamCarvingCore`, `SeamCarvingAccelerate`, `SeamCarvingMetal`, `SeamCarvingApple`, and `SeamCarvingVision` as the reusable engine. Add a shared multiplatform SwiftUI application layer that owns document state, mask editing, resize configuration, progress, and export; use thin platform adapters for file import/export, Photos, drag-and-drop, menus, and platform-specific presentation. Caire-inspired behavior is capability-aligned, not source-, detector-, or pixel-compatible.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XcodeGen, Swift Package Manager, Core Graphics, Core Image, Core Video, Vision, Metal.

**Spec:** `docs/ios-macos-seam-carving-implementation-research.md`, `docs/superpowers/plans/2026-08-21-seam-carving-swift-implementation.md`, and `README.md`.

## Progress update — 2026-08-23

- **Completed:** capability contract, opt-in pre-scale, shared model, shared
  SwiftUI editor, macOS/iOS targets, real PNG export, Vision face-aware
  service wiring, and CLI masks/face policy/pre-scale controls.
- **Verified:** package suite (100 tests), macOS App XCTest (26/26), iPhone
  17 Pro simulator App XCTest (26/26), macOS build, and generic iOS build.
- **Verified:** the physical iPad is online; signed App XCTest passes 26/26 and
  the Metal orientation screening passes 16/16. Fresh measurements are in
  `Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md`.
- **Current completion:** implementation and planned cross-platform acceptance
  gates are complete. The only remaining recommendation is a manual visual
  import/export smoke test on the installed app; automated gates are green.

## Global Constraints

- The engine remains usable without SwiftUI and without Vision.
- Core remains platform-independent and must not import SwiftUI, UIKit, AppKit, or Vision.
- macOS, iPhone, and iPad are first-class targets; no iPad-only assumptions.
- Preserve exact sequential seam semantics as the default resize mode.
- Preserve `.automatic` Metal full selection for supported shrink requests and CPU fallback for enlargement/adaptive ordering.
- Capability alignment does not require Caire/Pigo numerical compatibility.
- Do not add video temporal coherence, learned saliency, transport maps, or approximate batch seams in this plan.
- Every task ends with focused tests and a scoped commit.

## Capability Definition of Done

The aligned product must expose these capabilities:

| Capability | Owner | Acceptance criterion |
|---|---|---|
| Shrink and enlarge in both dimensions | Core/Apple | Output reaches requested pixel dimensions |
| Backward and forward energy | Core | Existing parity tests remain green |
| Protect and remove masks | Core/UI | Painted masks affect seam selection and remain aligned after edits |
| Object removal and optional restoration | Core/UI | Removal mask can be applied and original dimension restored |
| Face-aware protection | Vision/UI | Vision face regions become editable protection policy with explicit cadence |
| Caire-style large resize optimization | Planner/UI | Explicit opt-in pre-scale mode, never implicit in exact mode |
| CPU/Accelerate/Metal selection | Apple/UI | Backend and deterministic mode are visible and explainable |
| Progress, cancellation, and preview | Core/UI | User can cancel an active resize and retain the source document |
| Image import/export | Platform UI | macOS file URLs, iPhone/iPad Photos/files, and PNG/JPEG export work |
| Shared Apple experience | App | Same feature model works on macOS, iPhone, and iPad with adaptive layouts |

---

### Task 1: Freeze the capability matrix and public product contract

**Files:**
- Create: `docs/capability-matrix.md`
- Modify: `README.md`
- Modify: `Sources/SeamCarvingApple/SeamCarvingApple.docc/Backends.md`
- Test: existing Core, Apple, Vision, and Metal test suites

- [x] **Step 1: Document the Caire capability checklist**

Record the capability list above and explicitly classify each item as existing,
requires API exposure, or requires new implementation. State that Caire-inspired
face protection is a capability choice and not Pigo compatibility.

- [x] **Step 2: Identify API gaps before touching the GUI**

Verify that the GUI can construct:

```swift
ResizeOptions(
    energyMode: ...,
    dimensionOrder: ...,
    masks: ...,
    progress: ...
)
```

If a GUI feature cannot be expressed through existing public APIs, add the
smallest library-level API first and cover it with a Core or Apple test. Do not
put image-processing logic in a SwiftUI view.

- [x] **Step 3: Run the baseline gate**

```bash
swift test -c release --package-path . --parallel
```

Expected: all current tests pass before new behavior is added.

- [x] **Step 4: Commit the contract**

```bash
git add docs/capability-matrix.md README.md Sources/SeamCarvingApple/SeamCarvingApple.docc/Backends.md
git commit -m "docs: define Caire capability alignment"
```

### Task 2: Add explicit pre-scale planning as a Caire-aligned capability

**Files:**
- Modify: `Sources/SeamCarvingCore/ResizePlanner.swift`
- Modify: `Sources/SeamCarvingCore/SeamCarver.swift`
- Modify: `Sources/SeamCarvingApple/AppleSeamCarver.swift`
- Modify: `Sources/SeamCarvingApple/CGImageBridge.swift`
- Test: `Tests/SeamCarvingCoreTests/SeamCarverTests.swift`
- Test: `Tests/SeamCarvingAppleTests/AppleBridgeTests.swift`
- Modify: `README.md`

- [x] **Step 1: Specify the opt-in mode**

Add an explicit planner setting with two states:

```swift
public enum PreScaleStrategy: Sendable, Equatable {
    case none
    case lanczosThenExactResidual
}
```

Default must be `.none`. The setting must be part of resize options and must be
preserved through Apple and Vision adapters.

- [x] **Step 2: Write dimension and mask tests**

Test that `.none` produces the existing exact result. Test that the opt-in mode
pre-scales image and every protection/removal mask to the same intermediate
dimensions before residual seam carving. Test enlargement, shrink, mixed width/
height changes, and no-op resize.

- [x] **Step 3: Implement the planner boundary**

Keep Lanczos/Core Image work in Apple-level code where platform image APIs exist.
The Core target must receive a canonical RGBA8 image and masks after planning;
do not add Core Image imports to Core. If a target cannot use pre-scaling, throw
an explicit configuration error rather than silently changing semantics.

- [x] **Step 4: Benchmark the two modes separately**

Add benchmark labels `exact` and `lanczos-residual`. Never mix their timing or
parity results in one backend bucket.

- [x] **Step 5: Run and commit**

```bash
swift test --package-path . --filter 'SeamCarverTests|AppleBridgeTests' --parallel
git add Sources Tests README.md
git commit -m "feat: add opt-in pre-scale residual planning"
```

### Task 3: Expose complete Caire-aligned controls through a shared UI model

**Files:**
- Create: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ResizeDocument.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- Create: `Apps/SeamCarvingApp/Tests/ResizeConfigurationTests.swift`

**Interfaces:**

```swift
@MainActor
@Observable
final class AppModel {
    var document: ResizeDocument?
    var configuration: ResizeConfiguration
    var phase: ResizePhase
    var errorMessage: String?
    func importImage(_ source: ImageSource) async
    func resize() async
    func cancelResize()
    func export() async
}
```

```swift
struct ResizeConfiguration: Equatable, Sendable {
    var targetSize: PixelSize
    var energyMode: EnergyMode
    var dimensionOrder: DimensionOrder
    var backend: BackendPreference
    var deterministic: Bool
    var preScaleStrategy: PreScaleStrategy
    var faceProtection: FaceProtectionConfiguration?
}
```

- [x] **Step 1: Define document state separately from view state**

`ResizeDocument` owns source image, current masks, optional face regions, source
dimensions, target dimensions, and export metadata. Views must not own raw
pixel arrays or invoke `SeamEditor` directly.

- [x] **Step 2: Add configuration validation**

Validate positive target dimensions, mask dimensions, backend availability, and
face configuration before starting a task. Surface errors as typed state, not
fatal errors or alerts constructed deep inside the engine.

- [x] **Step 3: Add async task ownership and cancellation**

`AppModel` owns one resize task. Starting a new resize cancels the previous one;
progress updates are throttled on the main actor; cancellation returns the
document to an idle state with the source image intact.

- [x] **Step 4: Test model behavior without UI**

Test import, validation, cancellation, progress, backend selection, face
configuration, and export failure handling with fake Apple seam-carver services.

- [x] **Step 5: Commit the shared model**

```bash
git add Apps/SeamCarvingApp
git commit -m "feat: add multiplatform resize document model"
```

### Task 4: Build the shared SwiftUI editor for macOS, iPhone, and iPad

**Files:**
- Create: `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ImageCanvasView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ResizeControlsView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/MaskToolbarView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ProgressView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/ExportView.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/Accessibility.swift`
- Test: `Apps/SeamCarvingApp/Tests`

- [x] **Step 1: Implement the source/preview layout**

Use `NavigationSplitView` on macOS and iPad, with a compact navigation stack
on iPhone. The canvas must preserve image aspect ratio, show source/output or
before/after comparison, and never block the main actor during carving.

- [x] **Step 2: Implement resize controls**

Expose target width/height, lock aspect ratio, energy mode, dimension order,
backend, deterministic mode, and explicit pre-scale strategy. Explain when
Metal or CPU fallback will be used.

- [x] **Step 3: Implement mask painting**

Support protect/remove modes, brush size, opacity/strength, erase, undo/redo,
clear, and reset. Store masks in canonical pixel coordinates; convert only the
touch/gesture coordinates at the canvas boundary.

- [x] **Step 4: Implement face protection controls**

Offer enable/disable, policy preset, confidence/expansion controls where
supported, and detection cadence. Show detected regions before resize and let
the user remove an unwanted region from protection.

- [x] **Step 5: Implement progress and cancellation**

Show current dimensions, completed/total edits, backend, and a Cancel action.
On cancellation, retain the source image and masks.

- [x] **Step 6: Add UI tests**

Test configuration binding, disabled/enabled state during processing, mask
mode changes, cancellation, accessibility labels, and compact/regular layout
behavior. Image-processing output remains covered by engine tests.

- [x] **Step 7: Commit the shared UI**

```bash
git add Apps/SeamCarvingApp
git commit -m "feat: add shared seam carving editor UI"
```

### Task 5: Create the Apple multiplatform app targets

**Files:**
- Create: `Apps/SeamCarvingApp/project.yml`
- Create: `Apps/SeamCarvingApp/Sources/Shared/SeamCarvingApp.swift`
- Create: `Apps/SeamCarvingApp/Sources/macOS/MacPlatformServices.swift`
- Create: `Apps/SeamCarvingApp/Sources/iOS/IOSPlatformServices.swift`
- Create: `Apps/SeamCarvingApp/README.md`

- [x] **Step 1: Define XcodeGen targets**

Create separate macOS and iOS application targets sharing the same SwiftUI
source tree. The iOS target must support both iPhone and iPad; do not create a
separate iPad-only target. Set deployment floors to macOS 14 and iOS 17 to
match the package.

- [x] **Step 2: Add macOS platform services**

Implement NSOpenPanel/NSSavePanel, file URL drag-and-drop, menu commands,
keyboard shortcuts, and multi-window document creation. Keep these services
behind shared protocols.

- [x] **Step 3: Add iPhone/iPad platform services**

Implement PhotosPicker, UIDocumentPicker, share/export sheet, touch and Pencil
input for mask painting, and state restoration. Use the same shared model and
views as macOS.

- [x] **Step 4: Verify all three destinations**

Build and run:

```bash
xcodebuild -project Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj \
  -scheme SeamCarvingMac build
xcodebuild -project Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj \
  -scheme SeamCarvingIOS -destination 'generic/platform=iOS' build
```

Run the iOS UI tests on both an iPhone simulator and iPad simulator; run the
Metal/device integration suite on the connected physical iPad.

- [x] **Step 5: Commit platform targets**

```bash
git add Apps/SeamCarvingApp
git commit -m "feat: add macOS iPhone and iPad app targets"
```

### Task 6: Complete CLI capability alignment

**Files:**
- Modify: `Sources/SeamCarvingCLI/CLIOptions.swift`
- Modify: `Sources/seamcarve-cli/CLIEntry.swift`
- Modify: `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- Modify: `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`
- Modify: `README.md`

- [x] **Step 1: Add mask and policy arguments**

Support explicit input paths for protect and removal masks, mask strength,
face-protection preset, cadence, pre-scale strategy, and deterministic mode.
Each argument must map to an existing typed Swift configuration; do not add a
second CLI-only image-processing implementation.

- [x] **Step 2: Add parser tests and negative tests**

Cover documented examples, incompatible combinations, missing files, malformed
dimensions, unsupported formats, and invalid policy values.

- [x] **Step 3: Add end-to-end tests**

Run an input image with protect/remove masks and verify output dimensions and
that the mask pipeline is invoked. Keep process execution macOS-only as the
current test structure requires.

- [x] **Step 4: Commit CLI alignment**

```bash
git add Sources Tests README.md
git commit -m "feat: expose Caire-aligned controls in CLI"
```

### Task 7: Add cross-platform acceptance and performance gates

**Files:**
- Modify: `Benchmarks/README.md`
- Create: `Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md`
- Modify: `docs/capability-matrix.md`

- [x] **Step 1: Define the acceptance matrix**

Run the same image cases on macOS, iPhone, and iPad for:

```text
shrink / enlarge
vertical-only / horizontal-only / mixed dimensions
backward / forward energy
protect / removal / object restoration
face protection / both cadences
exact / lanczos-residual
CPU / Accelerate / Metal where available
```

- [x] **Step 2: Verify output and interaction behavior**

Assert dimensions, mask alignment, cancellation, export readability, and no
main-thread stalls. Compare pixels only between backends where exact parity is
promised; compare dimensions and protection invariants for pre-scale mode.

- [x] **Step 3: Record device-specific performance**

Keep iPad Metal full as the production signal. Record Mac, iPhone, and iPad
results separately; do not let a Mac result change the iOS backend policy.

- [x] **Step 4: Complete the matrix and commit documentation**

```bash
git add Benchmarks/README.md Apps/SeamCarvingApp/Tests docs/capability-matrix.md
git commit -m "docs: add multiplatform capability acceptance matrix"
```

## Final Review Checklist

- [x] Core library has no UI-framework imports.
- [x] Caire core capabilities are represented in the capability matrix.
- [x] Pre-scale is explicit opt-in and independently benchmarked.
- [x] Protect/remove/object restoration work from both API and GUI.
- [x] Vision face protection is available on iPhone, iPad, and macOS where Vision supports the target.
- [x] Shared SwiftUI UI runs on macOS, iPhone, and iPad.
- [x] macOS file workflows and iOS/iPadOS Photos/files workflows are both covered.
- [x] Metal full remains the preferred supported shrink backend on iOS/iPadOS after device validation.
- [x] CLI and GUI use the same typed configuration model.
- [x] All tests and platform build gates pass before declaring alignment complete.
