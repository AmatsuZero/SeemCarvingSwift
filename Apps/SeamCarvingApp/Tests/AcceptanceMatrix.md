# Apple-platform acceptance matrix

This is the release gate for the shared SwiftUI editor and the Caire-aligned
engine. A row is **verified** only when the listed command or device run has
actually completed; source inspection alone is not sufficient.

| Capability | macOS | iPhone simulator | iPad simulator | Physical iPad |
|---|---|---|---|---|
| App target builds | verified (`SeamCarvingMac`) | verified (`SeamCarvingIOS`) | covered by iOS target; run separately before release | pending device online |
| Shared XCTest/UI model tests | verified, 26/26 | verified, 26/26 | pending separate simulator run | pending device online |
| Core package tests | verified, 100 tests | covered by package/device host | covered by package/device host | previously verified Metal suite; rerun for release |
| Protect/remove masks | verified by Core + GUI + CLI mask E2E | GUI tests verified | pending simulator run | pending device run |
| Face protection, both cadences | Vision tests + macOS app compile | app compile/UI model verified | app compile/UI model verified | pending device run |
| Exact and Lanczos-residual resize | package tests verified | generic iOS build verified | generic iOS build verified | pending device run |
| PNG/JPEG export | PNG encoder and macOS save panel wired | PNG payload + ShareLink wired | PNG payload + ShareLink wired | pending device run |
| Metal full backend | package parity verified | generic build verified | prior iPad benchmark verified | release rerun pending |

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
