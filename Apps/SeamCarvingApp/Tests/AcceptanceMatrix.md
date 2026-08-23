# Apple-platform acceptance matrix

This is the release gate for the shared SwiftUI editor and the Caire-aligned
engine. A row is **verified** only when the listed command or device run has
actually completed; source inspection alone is not sufficient.

| Capability | macOS | iPhone simulator | iPad simulator | Physical iPad |
|---|---|---|---|---|
| App target builds | verified (`SeamCarvingMac`) | verified (`SeamCarvingIOS`) | verified (`SeamCarvingIOS`) | verified (`SeamCarvingIOS`) |
| Shared XCTest/UI model tests | verified, 26/26 | verified, 26/26 | verified, 26/26 | verified, 26/26 |
| Core package tests | verified, 100 tests | covered by package/device host | covered by package/device host | previously verified Metal suite; rerun for release |
| Protect/remove masks | verified by Core + GUI + CLI mask E2E | GUI tests verified | GUI tests verified | covered by signed App XCTest |
| Face protection, both cadences | Vision tests + macOS app compile | app compile/UI model verified | app compile/UI model verified | covered by signed App XCTest; Vision runtime not benchmarked |
| Exact and Lanczos-residual resize | package tests verified | generic iOS build verified | generic iOS build verified | app target verified; Metal benchmark below |
| PNG/JPEG export | PNG/JPEG encoder and macOS save panel wired | PNG/JPEG payload + ShareLink wired | PNG/JPEG payload + ShareLink wired | app target verified; manual picker flow still recommended |
| Metal full backend | package parity verified | generic build verified | prior iPad benchmark verified | verified, 16/16 orientation cases |

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
  -scheme SeamCarvingMac -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Apps/SeamCarvingApp/SeamCarvingApp.xcodeproj \
  -scheme SeamCarvingIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO test
```

The physical-device rows must remain open until the device is online and the
signed test host has been installed. An offline device is not treated as a
passing result.
