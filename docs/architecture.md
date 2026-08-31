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

## Platform capability targets

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

SeamCarvingAndroidBridge           (Swift dynamic bridge; Core only)
└── Android Gradle artifacts
    ├── seamcarving-android-core   (RGBA/mask API, native runtime)
    ├── seamcarving-android-bitmap (Bitmap conversion)
    ├── seamcarving-android-mlkit  (optional face masks)
    └── seamcarving-android        (core + Bitmap facade)
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

The Android bridge is also a one-way adapter: it depends on `SeamCarvingCore`
and presents JNI-friendly operations, while Core imports neither Android nor
ML Kit. Kotlin, rather than generated Java/JNI, is the stable Android external
API. `seamcarving-android-core` is the only Android artifact that packages the
Swift/C++ runtime closure; Bitmap, ML Kit, and facade AARs have no duplicate
native runtime libraries. The default facade intentionally excludes ML Kit so
face detection remains a visible, opt-in Android dependency.

Android pixels have the same canonical form as Core: upright, origin-zero,
straight-alpha, row-major RGBA8. The `Bitmap` artifact explicitly converts
Android packed `AARRGGBB` pixels through `getPixels()`/`setPixels()` rather
than treating `Bitmap` backing storage as a byte buffer. The optional ML Kit
artifact turns clamped face boxes into normal Core-compatible protection masks;
this Android logic is not added to Swift.

## Host validation and adapter delivery

The macOS command path and the isolated `SeamCarvingCoreTests` target verify
the portable Core module locally. The Linux/Windows matrix is configured as the
cross-host CI verification gate, but those hosts should only be described as
verified when repository CI evidence exists for `swift build --target
SeamCarvingCore` and the isolated Core tests. This gate validates the portable
algorithm module—not image codecs, UI adapters, CLI file I/O, or complete
application support on those hosts.

Android has a dedicated Gradle delivery gate: Swift 6.3.3 plus the matching
Android SDK and NDK r27d build the Core-only bridge for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`; Android device tests verify the RGBA/progress/
cancellation and Bitmap/ML Kit adapters; an external sample resolves only
locally published Maven coordinates. `minSdk` is 28. This is a CPU library
delivery surface, not support for the Apple CLI, SwiftUI editor, Apple image
codecs, Accelerate, Metal, or Vision on Android. Remote Maven publication and
signing remain a separately credentialed release action, not part of ordinary
CI.

The current command-line image codecs remain Apple-specific because
`SeamCarvingCLI` uses ImageIO and CoreGraphics. A future host-neutral split is
documented as `SeamCarvingCLIModel` (options, validation, and orchestration)
plus `SeamCarvingAppleCLIImageIO` (Apple image decoding and encoding). Those
are planned boundaries, not targets implemented by this release.
