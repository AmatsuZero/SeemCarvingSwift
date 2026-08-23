# Apple-platform acceptance matrix

This is the release gate for the shared SwiftUI editor and the Caire-aligned
engine. A row is **verified** only when the listed command or device run has
actually completed; source inspection alone is not sufficient.

| Capability | Mac Catalyst | iPhone simulator | iPad simulator | Physical iPad |
|---|---|---|---|---|
| App target builds | verified (`SeamCarvingApp`) | verified (`SeamCarvingApp`) | verified (`SeamCarvingApp`) | signed app/test host builds and installs |
| Shared XCTest/UI model tests | 31 unit tests verified; signed UI runner pending Mac Development identity | verified, 31 unit + 2 UI | verified, 31 unit + 2 UI | 31 unit tests verified; physical UI runner times out enabling automation |
| Core package tests | verified, 100 tests | covered by package/device host | covered by package/device host | previously verified Metal suite; rerun for release |
| Protect/remove masks | verified by Core + GUI + CLI mask E2E | GUI tests verified | GUI tests verified | covered by signed App XCTest |
| Face protection, both cadences | Vision tests + macOS app compile | app compile/UI model verified | app compile/UI model verified | covered by signed App XCTest; Vision runtime not benchmarked |
| Exact and Lanczos-residual resize | package tests verified | generic iOS build verified | generic iOS build verified | app target verified; Metal benchmark below |
| PNG/JPEG export | PNG/JPEG payload + ShareLink wired | PNG/JPEG payload + ShareLink wired | PNG/JPEG payload + ShareLink wired | pending manual picker smoke |
| Metal full backend | package parity verified | generic build verified | package/device-independent tests verified | prior signed screening: 16/16 orientation cases; release rerun pending |

## Fresh physical-iPad Metal screening — 2026-08-23

Device: `samzhjiang的iPad` (`00008122-0009185E26DA801C`), signed test host,
one sample per case, direct resize, 1280×720, 8-seam removal.

| Orientation / energy | CPU | Accelerate | Metal hybrid | Metal full |
|---|---:|---:|---:|---:|
| vertical / backward | 8360 ms | 6760 ms | 4600 ms | **47 ms** |
| vertical / forward | 3133 ms | 3127 ms | 3129 ms | **54 ms** |
| horizontal / backward | 11641 ms | 10081 ms | 4580 ms | **76 ms** |
| horizontal / forward | 6104 ms | 6110 ms | 3115 ms | **86 ms** |

## Commands

```sh
swift test -c release --package-path . --parallel
xcodebuild -project Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj \
  -scheme SeamCarvingApp -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj \
  -scheme SeamCarvingApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
```

The physical-device rows must remain open until the device is online, Developer
Mode is enabled, and the signed test host has been installed. An offline device
or a device with Developer Mode disabled is not treated as a passing result.

## Final regression record — 2026-08-23

- `swift test --package-path . --parallel`: 165 tests passed, including Metal
  parity and Metal shrink smoke tests.
- iPad Air 13-inch Simulator (iPadOS 26.5): 31 unit tests and 2 UI tests passed.
- Mac Catalyst: clean build and 31 unit tests passed. The known Metal toolchain
  search-path, AppIntents metadata, and `linkd.autoShortcut` messages remain
  Xcode/macOS diagnostics.
- Connected physical iPad (`00008122-0009185E26DA801C`): 31 unit tests passed
  with the personal development profile. UI tests were installed but the
  XCTest runner timed out while enabling automation mode before any UI test
  method ran. Developer Mode, pairing, unlock state, and display services were
  verified. Physical Metal screening remains represented by the earlier 16/16
  signed screening above and should be rerun only when a dedicated Metal test
  host is available.
