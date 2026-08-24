# CLI Target Layering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the current mixed `SeamCarvingCLI` target into portable command-model, arguments, orchestration, Apple-backend, and executable layers; reserve a first-class Windows CLI/backend extension point without platform conditionals in shared business code.

**Architecture:** Keep `SeamCarvingCLIModel` platform-neutral (Foundation + Core); translate argv in `SeamCarvingCLIArguments`; put backend/file-system capability contracts and execution flow in `SeamCarvingCLIOrchestration`; execute image I/O and Vision work in `SeamCarvingAppleCLIBackend`; retain `seamcarve-cli-apple` as the thin macOS process entry point. A documented `SeamCarvingWindowsCLIBackend`/`seamcarve-cli-windows` slot consumes the same contracts later. Preserve source compatibility temporarily through a deprecated `SeamCarvingCLI` facade that re-exports the current public APIs; new clients import the narrow target they need.

**Tech Stack:** Swift 6, SwiftPM, `swift-argument-parser` 1.6, XCTest, CoreGraphics/ImageIO/UniformTypeIdentifiers/Vision on Apple only.

**Spec:** `docs/architecture/cli-targets.md`; also obey `docs/architecture/platform-targets.md`.

## Global Constraints

- Do not move `swift-argument-parser` out of top-level `Package.dependencies`: SwiftPM has package-level resolution. Restrict its *target dependencies* instead.
- `SeamCarvingCLIModel` may import only Foundation and `SeamCarvingCore`; `SeamCarvingCLIOrchestration` may import only Foundation and `SeamCarvingCLIModel`. Neither may contain `#if os(...)`, Apple framework, Vision, WinSDK, or ArgumentParser imports.
- Do not claim that file-based CLI processing is cross-platform after this change; only the request/configuration model and batch scheduling are portable.
- Preserve current command flags, defaults, exit-code behavior, stdout/stderr contract, and end-to-end executable behavior.
- Update the boundary checker and docs in the same change; every new target requires a focused test target.

---

## 1. Lock current behavior with focused tests

- [ ] **Create four test targets in `Package.swift`:** `SeamCarvingCLIModelTests` (`SeamCarvingCLIModel`), `SeamCarvingCLIArgumentsTests` (`SeamCarvingCLIArguments`, `SeamCarvingCLIModel`), `SeamCarvingCLIOrchestrationTests` (`SeamCarvingCLIOrchestration`, model), and `SeamCarvingAppleCLITests` (Apple backend, arguments, orchestration, model). Add `seamcarve-cli-appleTests` if the executable invocation test cannot stay in AppleCLI tests without a reverse target dependency.
- [ ] **Move tests by responsibility:**
  - Split `Tests/SeamCarvingCLITests/BatchProcessorTests.swift`: move scheduler/path tests to `Tests/SeamCarvingCLIOrchestrationTests/BatchProcessorTests.swift`, using a fake `CLIFileSystem` and fake `CLIImageBackend`; place argv-specific batch configuration tests in `Tests/SeamCarvingCLIArgumentsTests/CLIArgumentsTests.swift`.
  - argv parsing/configuration cases in `CLIOptionsTests.swift` → `Tests/SeamCarvingCLIArgumentsTests/CLIArgumentsTests.swift`.
  - direct image processor/image I/O cases in `CLIEndToEndTests.swift` → `Tests/SeamCarvingAppleCLITests/AppleCLIProcessorTests.swift`.
  - subprocess cases (`testResizeImageViaExecutable`, stdin/stdout, and exit-code assertions) → `Tests/seamcarve-cli-appleTests/SeamCarveCommandTests.swift` if needed.
- [ ] Add test coverage before moving implementations:
  - model tests construct `CLIOptions` directly and verify configuration validation without Vision or ArgumentParser imports; orchestration tests verify batch planning/scheduling through fakes;
  - arguments tests verify all existing documented flag mappings, especially face policy/cadence and `--format`;
  - Apple tests prove model face requests map to current Vision policies and that format extension/explicit format output remains unchanged; they import `SeamCarvingCLIArguments` only for cases intentionally exercising argv parsing.
- [ ] Run the old target suite first: `rtk swift test --filter SeamCarvingCLITests` and record its total/passing result in the implementation PR notes.

## 2. Extract the portable command model

- [ ] Add `Sources/SeamCarvingCLIModel/` and create target/product declarations in `Package.swift`. Its dependencies are exactly `SeamCarvingCore`.
- [ ] Move and adapt these declarations into the model target:
  - `ResizeMode`, `SeamColor`, `SeamShape`, `CLIParseError`, `CLIConfigurationError`, `CLIExitCode`, `BatchConfiguration`, and `CLIConfiguration` from `CLIConfiguration.swift` / `CLIOptions.swift`;
  - `CLIProcessResult` from `CLIProcessor.swift`, plus batch job value types from `BatchProcessor.swift`;
  - the raw-value `CLIOutputFormat` enum from `CLIImageIO.swift`.
- [ ] Keep `CLIOutputFormat.parse(_:)` as a **public** model API (required by the arguments target), but move its `UTType`, ImageIO encoder, and file-extension I/O details to an AppleCLI extension (`CLIOutputFormat+AppleImageIO.swift`).
- [ ] Replace `FaceProtectionPolicy?` and `FaceDetectionCadence` in `CLIOptions` with model-owned `FacePolicyRequest?` and `FaceCadenceRequest`. Define the full semantic cases/defaults in `CLIOptions.swift` and make them `Sendable, Equatable`; they must express every current CLI value without importing Vision.
- [ ] Remove `CLIOptions.parse(_:)` and every reference to `CLIParsedArguments` from the model target. Expose a parser-neutral configuration constructor such as `CLIConfiguration.make(from: CLIOptions, inputDirectory: String?, outputDirectory: String?)` that retains today’s single/batch validation.
- [ ] Refactor `CLIExitCode.exitCode(for:)` so it classifies model errors only. `BatchProcessor` will move to orchestration and receive an injected backend `@Sendable (Error) -> String?` message classifier, used before its generic error string, so it no longer catches `CLIImageIOError`.
- [ ] Verify the isolation: `rtk swift test --filter SeamCarvingCLIModelTests` and a grep-based check that the model has none of `ArgumentParser`, `CoreGraphics`, `ImageIO`, `UniformTypeIdentifiers`, `SeamCarvingVision`, `SeamCarvingApple`.

## 3. Isolate ArgumentParser declarations and argv conversion

- [ ] Add `Sources/SeamCarvingCLIArguments/` and target `SeamCarvingCLIArguments` depending only on `SeamCarvingCLIModel` plus `.product(name: "ArgumentParser", package: "swift-argument-parser")`.
- [ ] Move `CLIParsedArguments`, `CLIArgumentParser`, all `ExpressibleByArgument` conformances, and argv-specific validation from `Sources/SeamCarvingCLI/CLIArgumentParser.swift` into this target.
- [ ] Change `CLIParsedArguments.makeOptions(...)` to create model `FacePolicyRequest`, `FaceCadenceRequest`, and `CLIOutputFormat` values. It must not construct Vision types or access ImageIO.
- [ ] Make `CLIArgumentParser.parseConfiguration(_:)` the public one-call argv → `CLIConfiguration` API: parse raw arguments, create model options, then invoke `CLIConfiguration.make(...)`. Keep `parse(_:)` / `parseOptions(_:)` only when tests or public compatibility need them; otherwise mark deprecated forwarding APIs deliberately.
- [ ] Update parser tests to import `SeamCarvingCLIArguments`, not `SeamCarvingVision`, and assert semantic request values instead of framework types.
- [ ] Verify `rtk swift test --filter SeamCarvingCLIArgumentsTests` and inspect `swift package show-dependencies`/manifest target edges to ensure no Apple target is in this target’s dependency closure.

## 4. Move Apple-only processing and adapt model requests

- [ ] Add `Sources/SeamCarvingCLIOrchestration/` and target `SeamCarvingCLIOrchestration` depending only on Foundation and `SeamCarvingCLIModel`. Move batch execution from the model into this target, behind `CLIFileSystem`; define `CLIImageBackend`, `CLIFileSystem`, `CLIBackendCapabilities`, and the process-result/error-classification contracts specified in `docs/architecture/cli-targets.md`.
- [ ] Define model `CLIBatchInput(inputPath:relativePath:)`. Require the file-system adapter to return slash-normalized root-relative paths, join the output root with an output-relative path, and create each output file’s parent directory. Orchestration retains deterministic sorting and extension rewriting but never calls `FileManager` or assumes a native separator.
- [ ] Refactor the existing Foundation directory implementation into an Apple assembly concern for now. The orchestration target receives it only through `CLIFileSystem`, so Windows path separators, case behavior, permissions, and enumeration can be tested/implemented independently later.
- [ ] Add `Sources/SeamCarvingAppleCLIBackend/` and target `SeamCarvingAppleCLIBackend` with direct dependencies `SeamCarvingCLIModel`, `SeamCarvingCLIOrchestration`, `SeamCarvingCore`, `SeamCarvingAppleRuntime`, `SeamCarvingAppleImaging`, and `SeamCarvingVision`.
- [ ] Move `CLIImageIO.swift`, `CLIProcessor.swift`, and `CLIDebugArtifacts.swift` into this target. Make `CLIProcessor` conform to `CLIImageBackend`; keep all CoreGraphics, ImageIO, UniformTypeIdentifiers, and Vision imports here only.
- [ ] Add `FacePolicyRequest+Vision.swift` (and cadence mapping if separate) with the only conversion from model face request values to `FaceProtectionPolicy` / `FaceDetectionCadence`. `CLIProcessor` must consume this adapter rather than change model types back to Vision types.
- [ ] Put `CLIOutputFormat` Apple-specific resolution/UTType/encoding APIs in `CLIOutputFormat+AppleImageIO.swift`; preserve output extension behavior for PNG, JPEG, BMP and standard output.
- [ ] Add `CLIAppleErrorClassifier` with concrete `static func exitCode(for: Error) -> CLIExitCode?` and `static func message(for: Error) -> String?` APIs. It must map `CLIImageIOError` to `.dataError` and its existing message; pass `message(for:)` to `BatchProcessor` and call `exitCode(for:)` before `CLIExitCode.exitCode(for:)` in the executable. Re-run direct processing tests including masks, debug artifacts, remote-input failure, and invalid output targets.
- [ ] Verify `rtk swift test --filter SeamCarvingAppleCLITests` and `rtk swift build --target SeamCarvingAppleCLIBackend`.

## 5. Thin the executable and preserve compatibility deliberately

- [ ] Rename the current platform-specific executable target/source directory to `seamcarve-cli-apple`. Update its command to directly import `SeamCarvingCLIModel`, `SeamCarvingCLIArguments`, `SeamCarvingCLIOrchestration`, and `SeamCarvingAppleCLIBackend`; its manifest target declares all four dependencies. It owns `AsyncParsableCommand`, console I/O, cancellation, and process exit only.
- [ ] Reserve (in docs and target naming only) `SeamCarvingWindowsCLIBackend` and `seamcarve-cli-windows`; do not create empty SwiftPM targets. Declare the Apple executable product/target only through a manifest-level macOS availability guard; never ship a Windows stub saying that the Apple CLI is unavailable. When Windows work begins, its backend must implement the established `CLIImageBackend`/`CLIFileSystem` contracts, publish the user-facing `seamcarve-cli` artifact on Windows, and add a Windows CI lane before it becomes a product.
- [ ] Keep a direct ArgumentParser dependency on `seamcarve-cli-apple` because `AsyncParsableCommand` is declared there. It must not import Apple image frameworks directly.
- [ ] Replace current `SeamCarvingCLI` implementation with a deprecated compatibility facade target that re-exports `SeamCarvingCLIModel`, `SeamCarvingCLIArguments`, `SeamCarvingCLIOrchestration`, and `SeamCarvingAppleCLIBackend`; preserve `import SeamCarvingCLI` source compatibility for this major version. Add deprecated facade forwarding APIs `CLIOptions.parse(_:)` and `CLIConfiguration.parse(arguments:)` that call `SeamCarvingCLIArguments`, then document narrow imports for new code and schedule facade removal for the next major release.
- [ ] Update `Package.swift` products: publish `SeamCarvingCLIModel`, `SeamCarvingCLIArguments`, `SeamCarvingCLIOrchestration`, and `SeamCarvingAppleCLIBackend`; keep `SeamCarvingCLI` as compatibility product for the v2 transition. Package the Apple executable artifact under the existing user-facing `seamcarve-cli` name even though its internal target is `seamcarve-cli-apple`.
- [ ] Ensure every concrete implementation target that imports ArgumentParser lists it directly: exactly `SeamCarvingCLIArguments` and `seamcarve-cli-apple`. The deprecated facade may depend on (but must not import) `SeamCarvingCLIArguments`; no non-CLI product may reach ArgumentParser.
- [ ] Run the executable integration suite, then manually smoke test help and a resize: `rtk swift run seamcarve-cli-apple --help` and the existing tiny-image command from `CLIEndToEndTests`.

## 6. Enforce boundaries and document the migration

- [ ] Extend `Scripts/check-target-boundaries.sh` to assert:
  - model imports only Foundation/Core;
  - arguments imports ArgumentParser/model but no Apple/Vision modules;
  - AppleCLIBackend contains all CLI CoreGraphics/ImageIO/UTType/Vision imports;
  - `seamcarve-cli-apple` contains no image-I/O imports;
  - orchestration contains the backend/file-system protocols but no Apple or Windows import;
  - `swift-argument-parser` appears only in the two implementation target dependency arrays; the facade may depend only on `SeamCarvingCLIArguments`.
- [ ] Update `.github/workflows/core-portability.yml` to build/test `SeamCarvingCLIModel` on the portable lane and keep AppleCLI/executable verification in the macOS lane.
- [ ] Update `docs/architecture/platform-targets.md`, add the target graph and dependency table from `docs/architecture/cli-targets.md`, and add a dated migration note to `docs/migrations/v2-platform-targets.md` describing the explicit `SeamCarvingCLIArguments` import requirement.
- [ ] Run final verification:
  ```sh
  rtk Scripts/check-target-boundaries.sh
  rtk swift build
  rtk swift test --parallel
  rtk swift run seamcarve-cli-apple --help
  ```
- [ ] Add a macOS CI integration job that builds the executable, resolves its bin path, sets `SEAMCARVE_CLI_PATH` for the executable test target, and fails if the subprocess tests are skipped. This is the regression guard for real command invocation, not just `--help`.
- [ ] Request an independent code review focused on dependency closure, public API compatibility, and executable error-code regression before merging.
