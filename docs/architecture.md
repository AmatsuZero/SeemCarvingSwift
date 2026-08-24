# Architecture

`SeamCarvingCore` owns image/mask value types, luma and energy semantics,
dynamic programming, seam editing, resize planning, and the CPU oracle. The
Accelerate and Metal targets implement backend contracts without changing
those semantics. Apple bridges normalize external images; Vision converts
face observations into ordinary Core masks.

## Locked semantics

- Canonical pixels are upright, origin-zero, sRGB-encoded straight-alpha RGBA8.
- Luma is computed from linear-sRGB components using
  `0.2126R + 0.7152G + 0.0722B`.
- Backward energy is clamp-to-edge 3×3 Sobel with `abs(gx) + abs(gy)`.
- Equal predecessor costs choose the smallest predecessor x.
- Seams are discovered and committed sequentially; cancellation is checked
  between edits and progress is emitted after each committed edit.
- Hard protection uses an infinite removal cost; face protection overrides
  removal energy.

## Memory and concurrency

The CPU reference uses two Float32 DP rows, an Int8 parent map, Float32
luma/energy planes, and a temporary UInt32 insertion map. Metal uses equivalent
row/parent/index resources plus declared luma, energy, and mask buffers.
Metal completion is awaited through a checked continuation and never blocks the
main actor.

Backend SPI is unsupported for ordinary clients. Backend parity is validated
against deterministic Core fixtures before performance samples are accepted.

## Platform capability targets (v2)

The algorithm target remains intentionally independent from platform image
objects. Capability targets point toward Core; Core never imports a platform
graphics, media, compute, or Vision framework.

```text
SeamCarvingCore
├── SeamCarvingAccelerate
├── SeamCarvingMetal
├── SeamCarvingAppleRuntime       (backend selection and RGBA8 API)
│   ├── SeamCarvingAppleImaging   (CGImage / CIImage)
│   ├── SeamCarvingCoreVideo      (CVPixelBuffer)
│   ├── SeamCarvingUIKit          (UIImage)
│   └── SeamCarvingAppKit         (NSImage)
└── SeamCarvingApple              (compatibility facade)
    └── re-exports Runtime + Imaging only
```

`SeamCarvingApple` preserves the CGImage import path, but it deliberately does
not export the mutually exclusive UIKit or AppKit adapters. Package clients
must add a product dependency for, and import, every capability they use:

```swift
// CGImage: v2 compatibility facade
import SeamCarvingCore
import SeamCarvingApple

// UIImage on iOS, iPadOS, or Mac Catalyst
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingUIKit

// NSImage on macOS
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingAppKit
```

This module reorganization is source-breaking at the package-product level in
v2. The Core pixel types, `AppleSeamCarver` type name, and its CGImage API
signatures remain stable.

## Host validation and future adapters

The macOS/Linux/Windows CI matrix validates `SeamCarvingCore` with a
Core-only cross-host build and test gate. It validates the portable algorithm
module—not image codecs, UI adapters, CLI file I/O, or complete application
support on those hosts. Wasm and Android are adapter-boundary-ready only; no
Wasm or Android support is shipped yet.

The current command-line image codecs remain Apple-specific because
`SeamCarvingCLI` uses ImageIO and CoreGraphics. A future host-neutral split is
documented as `SeamCarvingCLIModel` (options, validation, and orchestration)
plus `SeamCarvingAppleCLIImageIO` (Apple image decoding and encoding). Those
are planned boundaries, not targets implemented by this release.
