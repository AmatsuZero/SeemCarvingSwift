# GUI/CLI Capability Parity and CLI Ergonomics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Apple GUI expose the same user-facing image-processing capabilities as the CLI, and make the CLI parameters closer to Caire's ergonomic `input/output` model without breaking the current command syntax.

**Architecture:** Keep `CLIOptions`/`CLIConfiguration` as the domain configuration source of truth and extend them with explicit input/output specifications and resize modes. The GUI will bind to the same Core/Apple concepts through `ResizeConfiguration`, while platform adapters provide URL, file, Photos, export, and batch capabilities. CLI compatibility is additive: existing positional syntax remains valid, while `--input/-i` and `--output/-o` aliases provide the Caire-like form.

**Tech Stack:** Swift 6, Swift Argument Parser 1.x, SwiftUI, XCTest, CoreGraphics, ImageIO, Vision, Accelerate, Metal, PhotosPicker, fileImporter.

**Spec:** `docs/capability-matrix.md`, `docs/superpowers/plans/2026-08-23-caire-product-capability-alignment.md`, and the Caire feature baseline documented in the official README: https://github.com/esimov/caire

## Global Constraints

- Preserve `seamcarve-cli INPUT OUTPUT ...` and `-` stdin/stdout behavior.
- Additive CLI changes must preserve exit codes, binary stdout purity, and existing batch/debug/URL/BMP behavior.
- Do not claim Pigo compatibility; Vision remains the Apple face detector.
- GUI and CLI must call shared Core/Apple services; do not duplicate seam-carving algorithms in SwiftUI.
- GUI defaults remain exact pixel resize, backward Sobel energy, automatic backend, non-deterministic mode, and no debug artifacts.
- Every task must add/adjust tests before implementation and end with an independent commit.
- Do not modify or commit the user-owned untracked `CODE_REVIEW.md`.
- iOS/iPadOS must not expose filesystem-only controls that cannot work on the platform; unsupported operations require a visible explanation.

---

## Target parameter contract

The new CLI form is:

```text
seamcarve-cli --input INPUT --output OUTPUT --width WIDTH --height HEIGHT
seamcarve-cli -i INPUT -o OUTPUT --percentage PERCENT
seamcarve-cli --input INPUT --output OUTPUT --square
seamcarve-cli --input INPUT_DIR --output OUTPUT_DIR --recursive --concurrency N ...
```

The existing form remains valid:

```text
seamcarve-cli INPUT OUTPUT --width WIDTH --height HEIGHT
```

`INPUT` is a local path, `http(s)` URL, or `-`; `OUTPUT` is a local path or `-`. Directories are selected explicitly by `--input-dir/--output-dir`; do not infer directory mode from arbitrary path strings. `--percentage` remains a typed numeric value rather than Caire's boolean percentage switch, avoiding the ambiguity of changing the meaning of width/height.

## Task 1: Freeze the parity contract and shared GUI state

**Files:**
- Modify: `docs/capability-matrix.md`
- Modify: `Sources/SeamCarvingCLI/CLIOptions.swift`
- Modify: `Sources/SeamCarvingCLI/CLIConfiguration.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Test: `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`

**Interfaces:**
- `ResizeMode` remains the shared semantic model for `.exact(width:height)`, `.percentage(Float)`, and `.square`.
- Add GUI bindings for `blurRadius: Int?`, `sobelThreshold: Float?`, `protectWeight: Float`, and `removalWeight: Float` in `ResizeConfiguration`.
- Normalize parser values into the existing `CLIOptions` fields; introduce a typed `CLIInput`/`CLIOutput` representation in `CLIConfiguration.swift` to distinguish single-file, stream, URL, and directory values without changing the public `CLIOptions` compatibility surface.

- [ ] **Step 1: Write parity tests** for every current CLI option and every GUI configuration value, asserting that defaults and cross-field constraints are identical.
- [ ] **Step 2: Run the focused tests** and confirm the new parity assertions fail for GUI-only missing fields.
- [ ] **Step 3: Add the shared typed fields and validation** without changing the default resize behavior.
- [ ] **Step 4: Run CLI and GUI focused tests** and confirm invalid forward-energy plus blur/Sobel, invalid weights, and conflicting resize modes are rejected.
- [ ] **Step 5: Update the matrix** with explicit “CLI”, “GUI”, and “shared service” status columns.
- [ ] **Step 6: Commit** with `docs: define GUI and CLI parity contract`.

## Task 2: Add Caire-like CLI input/output aliases

**Files:**
- Modify: `Sources/SeamCarvingCLI/CLIArgumentParser.swift`
- Modify: `Sources/SeamCarvingCLI/CLIConfiguration.swift`
- Modify: `Sources/seamcarve-cli/SeamCarveCommand.swift`
- Modify: `README.md`
- Test: `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- Test: `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`

**Interfaces:**
- `@Argument` positional input/output remain supported.
- Add `@Option(name: [.customShort("i"), .customLong("input")])` and matching `output` aliases, with a validation rule that positional and named values cannot both be supplied.
- Preserve `--input-dir/--output-dir` for batch mode and reject mixing single-image and directory forms.

- [ ] **Step 1: Add failing parser tests** for `--input`, `--output`, `-i`, `-o`, duplicate positional/named inputs, missing values, and batch conflicts.
- [ ] **Step 2: Add failing process tests** proving named input/output preserve URL, stdin, stdout, and BMP behavior.
- [ ] **Step 3: Implement parser aliases** and normalize both syntaxes into the existing domain configuration.
- [ ] **Step 4: Keep `--percentage`, `--square`, `--format`, and all existing long options unchanged**; add only documented short aliases where they do not conflict with existing names.
- [ ] **Step 5: Update help and README examples** to show the recommended named form and the retained positional form.
- [ ] **Step 6: Run parser and E2E tests**, including stdout byte checks and stable exit codes.
- [ ] **Step 7: Commit** with `feat: add ergonomic CLI input output aliases`.

## Task 3: Add GUI percentage, square, blur, Sobel, and weight controls

**Files:**
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeControlsView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/MaskToolbarView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`
- Test: `Apps/SeamCarvingApp/Tests/ResizeConfigurationTests.swift`

**Interfaces:**
- Add a resize-mode picker with exact, percentage, and square modes.
- Exact mode shows width/height; percentage mode shows one percentage value; square mode shows the derived short-edge target and disables contradictory fields.
- Add optional blur radius and Sobel threshold controls, disabled or visibly rejected for forward energy.
- Add numeric protection/removal weight controls with validation and retain brush opacity as a separate mask-painting setting.

- [ ] **Step 1: Write UI-model tests** for mode-to-target conversion, square short-edge semantics, percentage rounding, and invalid energy/weight combinations.
- [ ] **Step 2: Run them to verify missing GUI state/control behavior.**
- [ ] **Step 3: Implement bindings** and pass the resulting `ResizeOptions` into the existing service path.
- [ ] **Step 4: Add accessibility identifiers** for mode, percentage, blur, Sobel, protect weight, and removal weight controls.
- [ ] **Step 5: Run macOS and iOS GUI XCTest** and confirm defaults remain unchanged.
- [ ] **Step 6: Commit** with `feat: expose CLI resize controls in GUI`.

## Task 4: Add GUI URL import, BMP export, and multi-image batch workflow

**Files:**
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ContentView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ExportView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeDocument.swift`
- Modify: `Apps/SeamCarvingApp/Sources/macOS/MacPlatformServices.swift`
- Modify: `Apps/SeamCarvingApp/Sources/iOS/IOSPlatformServices.swift`
- Create: `Apps/SeamCarvingApp/Sources/Shared/BatchJobModel.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`
- Test: `Apps/SeamCarvingApp/Tests/BatchJobModelTests.swift`

**Interfaces:**
- Add `URLImageSource` through the same import service, restricted to `http`/`https` and reporting typed network errors.
- Extend `ExportFormat` with `.bmp` and use ImageIO for PNG/JPEG/BMP encoding.
- Add a batch job model with `queued/running/completed/failed/cancelled`, bounded concurrency, per-item errors, and platform-specific output destination selection.

- [ ] **Step 1: Write service tests** for URL success/failure, BMP encode/decode, export-before-completion, cancellation, and partial batch failure.
- [ ] **Step 2: Run the tests to establish the missing behavior.**
- [ ] **Step 3: Implement URL import and BMP export** using ImageIO/Foundation, not duplicated image-processing code.
- [ ] **Step 4: Implement the batch queue** by reusing the existing bounded `BatchProcessor` semantics; do not start an unbounded task per selected image.
- [ ] **Step 5: Add platform UI**: macOS folder/file selection; iOS/iPadOS multi-selection from Photos/Files where supported; show a clear limitation when a destination cannot be selected.
- [ ] **Step 6: Run macOS and iOS simulator GUI XCTest** and perform an iPad smoke test for Photos/Files and export/share.
- [ ] **Step 7: Commit** with `feat: add GUI image I/O and batch parity`.

## Task 5: Add GUI seam debug visualization and artifact export

**Files:**
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ImageCanvasView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeControlsView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ExportView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeDocument.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`
- Test: `Tests/SeamCarvingCoreTests/SeamDebugArtifactsTests.swift`

**Interfaces:**
- Reuse `SeamObservation`/`SeamDebugArtifacts` from Core and the CLI artifact contract; GUI debug must observe actual seams, not infer them from final pixels.
- Add debug enabled, color, shape, and artifact metadata to the document state.
- When Metal cannot provide seam observation, show the same explicit CPU fallback diagnostic used by CLI.

- [ ] **Step 1: Write tests** for debug toggle, line/points rendering, color/alpha, cancellation, output naming, and Metal fallback messaging.
- [ ] **Step 2: Implement model wiring** with debug disabled by default and no observer allocation in normal mode.
- [ ] **Step 3: Add canvas overlay** in current-image coordinates and an export/share action for the manifest and overlay files.
- [ ] **Step 4: Run Core, macOS, and iOS tests** and verify debug artifacts do not pollute ordinary image export.
- [ ] **Step 5: Commit** with `feat: add GUI seam debug workflow`.

## Task 6: Complete face and mask parameter parity

**Files:**
- Modify: `Apps/SeamCarvingApp/Sources/Shared/FaceProtectionControlsView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/MaskToolbarView.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/ResizeConfiguration.swift`
- Modify: `Apps/SeamCarvingApp/Sources/Shared/AppModel.swift`
- Test: `Apps/SeamCarvingApp/Tests/AppModelTests.swift`

**Interfaces:**
- Expose all CLI face policy controls that have GUI meaning: policy, cadence, confidence, expansion, and explicit exclusion.
- Expose hard/soft protection semantics and independent removal/protection weights while keeping painted mask strength separate.
- Keep stable face IDs and never silently disable protection after detector failure.

- [ ] **Step 1: Add fake-detector/fake-service tests** for policy, cadence, excluded regions, hard/soft masks, and weight propagation.
- [ ] **Step 2: Implement missing controls and validation.**
- [ ] **Step 3: Run macOS/iOS tests and a real Vision face-image smoke test where an image is available.**
- [ ] **Step 4: Commit** with `feat: complete GUI face and mask parity`.

## Task 7: Final cross-platform acceptance and documentation

**Files:**
- Modify: `docs/capability-matrix.md`
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-08-23-gui-cli-parity-and-cli-ergonomics.md`
- Test: `Tests/SeamCarvingCLITests/CLIOptionsTests.swift`
- Test: `Tests/SeamCarvingCLITests/CLIEndToEndTests.swift`
- Test: `Apps/SeamCarvingApp/Tests/*`

- [ ] **Step 1: Add a CLI parameter compatibility table** covering positional, named, short aliases, defaults, mutual exclusions, stream behavior, and batch behavior.
- [ ] **Step 2: Add a GUI parity table** marking exact/percentage/square, masks, face, weights, energy controls, URL/BMP, batch, debug, and platform support.
- [ ] **Step 3: Run `swift package resolve` and the full package suite.**
- [ ] **Step 4: Run clean macOS and iOS GUI XCTest with separate DerivedData and module-cache directories.**
- [ ] **Step 5: Run iPad device App XCTest and Metal screening; record device and test counts.**
- [ ] **Step 6: Run `git diff --check`, inspect `git status --short`, and ensure only `CODE_REVIEW.md` remains untracked.**
- [ ] **Step 7: Commit** with `docs: complete GUI and CLI parity audit`.

## Definition of Done

- The GUI exposes every single-image CLI capability: exact/percentage/square resize, energy controls, backend/deterministic, masks/weights, face policy/cadence, URL/file/Photos import, PNG/JPEG/BMP export, and seam debug artifacts.
- GUI batch processing exists where the platform supports multi-selection and destination selection, with bounded concurrency and visible per-item failures; unsupported platform paths are explicit rather than silently absent.
- CLI supports both the existing positional syntax and Caire-like `--input/-i` + `--output/-o` syntax.
- CLI and GUI use the same Core/Apple semantics for resize mode, masks, weights, face policy, debug observation, and cancellation.
- Full package tests, clean macOS/iOS GUI tests, and available iPad device tests pass.
- Documentation distinguishes capability alignment from Caire syntax/Pigo/pixel compatibility.
