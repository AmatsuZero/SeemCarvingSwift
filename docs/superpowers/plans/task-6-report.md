# Task 6 Report: Target Boundaries and v2 Migration

## Delivered

- Added executable `Scripts/check-target-boundaries.sh`.
  - `SeamCarvingCore` accepts only `Foundation` and `Dispatch` imports and no
    conditional compilation.
  - `SeamCarvingAppleRuntime` accepts only `Foundation`, `SeamCarvingCore`,
    `SeamCarvingAccelerate`, and `SeamCarvingMetal`, with no conditional
    compilation.
  - `SeamCarvingAppleImaging` rejects UIKit/AppKit/CoreVideo imports and all
    conditional compilation; `SeamCarvingCoreVideo` rejects UIKit/AppKit and
    all conditional compilation.
  - UIKit/AppKit reject sibling adapter-framework imports and
    `targetEnvironment`; each Swift source file must have only its outer,
    whole-file `#if canImport(<own framework>)` guard.
- Wired the boundary script into `.github/workflows/core-portability.yml`
  before the Core build/test commands.
- Added `docs/migrations/v2-platform-targets.md` with v1-to-v2 import/product
  mapping and the exact `SeamCarvingApple` compatibility-facade scope.
- Updated the architecture specification and implementation plan to document
  the controller-approved narrow UIKit/AppKit compile-guard exception.

## Verification

All direct commands below used a 120-second timeout (or 15 seconds for the
boundary script), so no command was allowed to wait indefinitely.

| Command | Result |
| --- | --- |
| `bash -n Scripts/check-target-boundaries.sh` | Passed |
| `timeout 15s bash Scripts/check-target-boundaries.sh` | Passed (exit 0) |
| `swift build --target SeamCarvingCore` | Passed |
| `swift test --filter SeamCarvingCoreTests` | Passed: 68 tests |
| `swift test --filter SeamCarvingAppleRuntimeTests` | Passed: 7 tests |
| `swift test --filter SeamCarvingAppleImagingTests` | Passed: 13 tests |
| `swift test --filter SeamCarvingCoreVideoTests` | Passed: 2 tests |
| `swift test --filter SeamCarvingAppKitTests` | Passed: 1 test |
| `git diff --check` | Passed |

The initial sandboxed SwiftPM invocation could not evaluate the manifest
because `sandbox-exec` returned `Operation not permitted`; the same bounded
commands were then run outside that sandbox and passed.

## Known verification limits

- UIKit Simulator tests were **not** run: the prior task recorded an
  unavailable CoreSimulator service/no discoverable runtime. This task does not
  claim Simulator success.
- The full `swift test --parallel` suite was intentionally not rerun in Task 6;
  focused package tests above cover the touched boundary policy and its direct
  module surfaces.
- A temporary negative-fixture experiment for the shell script was interrupted
  by the controlling session after 120 seconds and produced no usable result;
  it is not counted as verification. The committed script itself was syntax
  checked and run successfully against the repository.
