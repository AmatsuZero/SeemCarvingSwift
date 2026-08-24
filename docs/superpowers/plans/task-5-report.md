# Task 5 Report: Adopt Capability-Based Platform Modules

## Delivered

- Retained `Sources/SeamCarvingApple/Exports.swift` as the v2 compatibility
  facade. It re-exports **only** `SeamCarvingAppleRuntime` and
  `SeamCarvingAppleImaging`.
- Changed the package dependency graph so `SeamCarvingVision` and
  `SeamCarvingCLI` name Runtime and Imaging directly; Benchmark names Imaging
  directly; the facade no longer depends on Core; and the CLI executable names
  only its actual CLI/ArgumentParser inputs.
- Replaced internal facade imports in Vision, CLI, Benchmark, the SwiftUI app,
  app tests, and Vision/Imaging package tests with their actual capability
  imports. The test-host XcodeGen specification now gives Vision and CLI tests
  Runtime + Imaging rather than the facade.
- Updated the SwiftUI app and its unit-test target to depend directly on
  Runtime, Imaging, and the UIKit adapter used by the iOS/Catalyst app.
- Registered the UIKit package test target. The UIKit and AppKit adapter source
  files/tests now use an outer `canImport` availability guard so a host that
  lacks that framework can still build the package's other targets. This was
  necessary for the required macOS SwiftPM suite and generic iOS package build;
  it does not mix UIKit/AppKit APIs or add a Catalyst branch to either adapter.
- Updated `README.md`, `README.zh-CN.md`, `docs/architecture.md`,
  `docs/capability-matrix.md`, and the Apple DocC backend page with v2 CGImage,
  UIKit, and AppKit import examples; Core-only cross-host-gate scope; future
  Wasm/Android status; and the documentation-only
  `SeamCarvingCLIModel` / `SeamCarvingAppleCLIImageIO` boundary.

## Verification evidence

### Passed

- `swift test --parallel` completed after the Runtime/Imaging dependency
  migration: **169 tests passed** on macOS. UIKit test sources are intentionally
  unavailable to that host and therefore compile to an empty target.
- `xcodebuild -scheme SeamCarvingSwift-Package -destination
  'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` completed after the
  AppKit availability guard: **BUILD SUCCEEDED**. This compiles the real UIKit
  adapter for iOS and verifies that the unsupported AppKit target is safely
  absent from that destination.
- `git diff --check` passed.

### Unavailable / not rerun

- The UIKit simulator test remains unavailable: CoreSimulator previously
  reported an invalid service connection and no discoverable runtimes. Per the
  user instruction, it was not retried or waited on indefinitely.
- A final SwiftPM-suite retry was attempted after the final availability-guard
  and documentation edits. The sandboxed invocation failed before tests began
  because Swift could not write its shared Clang module cache. The approved
  rerun then produced no output for 95 seconds and was terminated at the
  user's direction. The earlier 169-test success plus the post-change generic
  iOS package build are the available verification evidence.
- `xcodegen generate --spec Apps/SeamCarvingApp/project.yml` cannot currently
  validate the app project because the pre-existing spec references the absent
  `Apps/SeamCarvingApp/Sources/iOS` directory. The dependency declarations were
  updated in the specification, but app-project generation/build remains a
  separate repository-layout blocker.
