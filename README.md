# SeamCarvingSwift

**Language / 语言:** [English](README.md) · [中文](README.zh-CN.md)

SeamCarvingSwift is a Swift 6 package for content-aware image resizing on
iOS 17+ and macOS 14+. It provides a platform-independent RGBA8 seam-carving
engine, optional Accelerate and Metal backends, Apple image bridges, Vision
face protection, a CLI, and one SwiftUI app target shared by iPhone, iPad, and
Mac Catalyst.

## Choose a starting point

| You want to... | Start here |
|---|---|
| Understand the module boundaries and data flow | [Architecture](docs/architecture.html) · [中文](docs/architecture-zh.html) |
| Understand energy, seams, masks, enlargement, and Metal | [Algorithm principles](docs/principles.html) · [中文](docs/principles-zh.html) |
| Integrate the Swift libraries | [Swift API guide](docs/api.html) · [中文](docs/api-zh.html) |
| Resize files from a shell or in a batch | [CLI guide](docs/cli.html) · [中文](docs/cli-zh.html) |
| Run the iPhone/iPad/Catalyst editor | [App guide](docs/app.html) · [中文](docs/app-zh.html) |
| Review the implemented capability contract | [Capability matrix](docs/capability-matrix.html) · [中文](docs/capability-matrix-zh.html) |
| Browse the hosted documentation | [GitHub Pages site](docs/index.html) · [中文](docs/index-zh.html) |

## Quick start

### Build the package

```sh
swift build
swift test
swift run seamcarve-cli --help
```

The package declares Swift tools version 6.0 and platform floors of iOS 17 and
macOS 14. Its only external package dependency is Apple's
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser), used
by the CLI syntax layer.

### Use the Core API

Core accepts upright, origin-zero, straight-alpha RGBA8 bytes. It does not
import UIKit, AppKit, Core Image, Vision, Metal, or Accelerate.

```swift
import SeamCarvingCore

let image = try RGBA8Image(width: 4, height: 4, pixels: pixels)
let target = try PixelSize(width: 3, height: 4)
let result = try await SeamCarver().resize(image, to: target)
```

See the [API guide](docs/api.html) for masks, progress, cancellation,
enlargement, and the Apple facade.

### Use the Android Gradle library

Android is available as a CPU-only Gradle library with `minSdk = 28`. The
published core AAR contains `arm64-v8a`, `armeabi-v7a`, and `x86_64` native
libraries; application consumers install neither Swift nor the Android NDK.

The default facade gives an Android app the RGBA core and `Bitmap` adapters:

```kotlin
repositories {
    mavenCentral() // use a released version after the Maven Central release gate
}

dependencies {
    implementation("io.github.seamcarving:seamcarving-android:<version>")
}
```

`<version>` is intentionally not a promise that a snapshot has been uploaded:
the repository currently verifies release candidates by publishing to
`Android/build/local-maven`, and a separate signed release workflow is required
before a version is available from Maven Central. A developer testing that
local publication must add its filesystem Maven repository explicitly; an
ordinary application should use only the released Maven Central coordinate.

For a buffer-only integration depend on
`seamcarving-android-core`; `seamcarving-android-bitmap` adds `Bitmap`
conversion. `seamcarving-android-mlkit` is opt-in and supplies face-protection
masks—it is deliberately excluded from the default facade. The Kotlin API,
RGBA contract, progress/cancellation, `Bitmap` ownership, mask semantics, and
local-consumer troubleshooting are documented in [Android/README.md](Android/README.md).

### Import the Apple capability you use

The v2 `SeamCarvingApple` product is a compatibility facade for the CGImage
surface only: it re-exports `SeamCarvingAppleRuntime` and
`SeamCarvingAppleImaging`. UIKit and AppKit are separate products and must be
imported explicitly.

```swift
// CGImage API / v2 compatibility facade
import SeamCarvingCore
import SeamCarvingApple

let carver = try AppleSeamCarver()
let output = try await carver.resize(cgImage, toPixelSize: target)
```

```swift
// iOS, iPadOS, and Mac Catalyst UIImage overload
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingUIKit

let output = try await AppleSeamCarver().resize(uiImage, toPixelSize: target)
```

```swift
// macOS NSImage overload
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingAppKit

let output = try await AppleSeamCarver().resize(nsImage, toPixelSize: target)
```

Add the matching SwiftPM product dependency for every directly imported module;
do not use the facade to conceal a Runtime, Imaging, UIKit, or AppKit dependency.

### Cross-host boundary status

`SeamCarvingCore` is protected by a macOS-local **Core-only build and isolated
test gate** plus a macOS/Linux/Windows CI verification matrix. Linux and
Windows should only be called verified when repository CI evidence exists for
`swift build --target SeamCarvingCore` and the isolated Core test target. The
gate validates the portable algorithm target, not complete image I/O or
application support on those hosts. The repository also contains an
[experimental static browser WASM demo](Examples/WasmDemo/README.md) that
runs the CPU Core path locally in a Worker. It is not a declaration of general
WASM platform, image-I/O library, CLI, or application support. Android has a
separate CPU Gradle-library delivery surface; it does not make the Apple CLI,
editor, image codecs, Metal, or Vision capabilities available on Android.

### Run the CLI

```sh
swift run seamcarve-cli input.jpg output.png --width 1200 --height 800
swift run seamcarve-cli input.jpg output.jpg --percentage 75 --backend automatic
swift run seamcarve-cli --input-dir photos --output-dir resized \
  --width 1200 --height 800 --recursive --concurrency 2
```

`seamcarve-cli` accepts local paths, explicit `http(s)` URLs, and `-` for
stdin/stdout. Exact dimensions, percentage, square, backend, energy, order,
pre-scale, masks, face protection, debug artifacts, output format, and batch
options are documented in the [CLI guide](docs/cli.html). The examples there
are derived from `swift run seamcarve-cli --help` and the parser sources.

The current CLI image I/O is intentionally Apple-specific: it uses ImageIO and
CoreGraphics. A future cross-host split will keep options, validation, and
pipeline orchestration in `SeamCarvingCLIModel`, while moving these codecs into
`SeamCarvingAppleCLIImageIO`. Those are documented future boundaries only; this
release does not add non-Apple image I/O.

### Build the Apple app

The app uses a single SwiftUI target for iPhone, iPad, and Mac Catalyst. The
Xcode project is generated locally from `Apps/SeamCarvingApp/project.yml` and
is intentionally ignored by Git.

```sh
cd Apps/SeamCarvingApp
xcodegen generate
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'generic/platform=iOS' build
xcodebuild -project SeamCarvingApp.xcodeproj -scheme SeamCarvingApp \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO build
```

Follow the [app guide](docs/app.html) for import, target dimensions, masks,
face protection, export, signing, and platform-specific testing.

## What the engine does

The Core engine removes or inserts one connected seam at a time. It supports:

- backward Sobel and forward-luma energy;
- width-first, height-first, or adaptive normalized-cost ordering;
- hard and weighted soft protection masks plus weighted removal masks;
- dedicated object removal with optional restoration of the original size;
- progress callbacks, cooperative cancellation, and seam observation hooks;
- exact sequential resize semantics by default;
- explicit Apple-only Lanczos pre-scaling followed by exact residual carving;
- CPU, Accelerate, and optional Metal backend selection through
  `AppleSeamCarver`;
- optional Vision face protection with Caire-inspired or Vision-quality policy
  and detect-once or re-detect-each-pass cadence.

The [capability matrix](docs/capability-matrix.md) is the authoritative product
status record. Caire is reference material for capability alignment; this
project does not claim Caire compatibility or use Caire's detector.

## Architecture at a glance

```text
SeamCarvingCore
    ├── SeamCarvingAccelerate
    ├── SeamCarvingMetal
    ├── SeamCarvingAppleRuntime
    │   ├── SeamCarvingAppleImaging ──┬── SeamCarvingVision
    │   │                             ├── SeamCarvingCLI / seamcarve-cli
    │   │                             └── shared SwiftUI app
    │   ├── SeamCarvingCoreVideo
    │   ├── SeamCarvingUIKit
    │   └── SeamCarvingAppKit
    └── SeamCarvingApple (CGImage compatibility facade)

Android Gradle artifacts (separate distribution boundary)
    ├── seamcarving-android-core (CPU RGBA API + Swift runtime)
    ├── seamcarving-android-bitmap (Bitmap adapter)
    ├── seamcarving-android-mlkit (optional ML Kit masks)
    └── seamcarving-android (core + Bitmap facade)
```

Core owns image and mask semantics, energy, dynamic programming, seam editing,
planning, and the CPU oracle. AppleRuntime selects the backend, AppleImaging
bridges CGImage/Core Image, and the CoreVideo/UIKit/AppKit targets own their
respective system-image types. Vision turns face observations into Core masks.
See the [architecture guide](docs/architecture.html) for the full data flow.

## Backend and algorithm notes

`.automatic` tries Metal, then Accelerate, then CPU. Use `.deterministic` or
`.cpu` when reproducible reference behavior is more important than speed.
Metal is an optional asynchronous backend: it accelerates supported shrink
paths, while horizontal edits use CPU transposition and enlargement/adaptive
ordering intentionally use the CPU reference path. CLI debug artifacts also
force CPU because seam observation is not available on the Metal path.

The default pre-scale strategy is `.none`; the engine does not silently
Lanczos-scale conventional resizes. `.lanczosThenExactResidual` is an explicit,
Apple-platform-only approximation that scales the image and masks first.

The project does not implement video temporal coherence, learned saliency,
transport maps, MLX, Core ML, HDR/extended-range input, or a GPU-only contract.

## Testing and verification

Package tests:

```sh
swift test --package-path . --parallel
```

The latest recorded regression has 169 package tests passing, including Metal
parity and shrink smoke tests. The Apple app acceptance record also contains:

- iPhone and iPad Simulator: 31 unit tests plus 2 UI tests passing;
- Mac Catalyst: clean build and 31 unit tests passing;
- connected physical iPad: signed app/test host and 31 unit tests passing;
- physical iPad UI XCTest: **not passing** because the runner times out while
  enabling automation mode before any UI test method runs;
- physical Metal: an earlier signed 16/16 screening is recorded, but a fresh
  release run requires a dedicated signed Metal test host.

See [`Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md`](Apps/SeamCarvingApp/Tests/AcceptanceMatrix.md)
for commands, dates, and the exact limitations. System messages such as
LaunchServices `LSPrefs`, `FSFindFolder`, `ViewBridge`, or task-port warnings
are Xcode/macOS diagnostics when the app otherwise launches; they are not
application API guarantees or errors to suppress with entitlements.

## GitHub Pages

The site is dependency-free static HTML/CSS. To publish it, open repository
**Settings → Pages**, choose **Deploy from a branch**, select the desired branch,
and set the folder to **`/docs`**. No Jekyll, Node, Python, or documentation
build step is required.

## Repository layout

```text
Sources/SeamCarvingCore/        platform-independent engine
Sources/SeamCarvingAccelerate/  Accelerate backend
Sources/SeamCarvingMetal/       Metal backend and shader
Sources/SeamCarvingAppleRuntime/ Apple backend selection and RGBA8 API
Sources/SeamCarvingAppleImaging/ CGImage/CIImage adapter
Sources/SeamCarvingCoreVideo/    CVPixelBuffer adapter
Sources/SeamCarvingUIKit/        UIImage adapter
Sources/SeamCarvingAppKit/       NSImage adapter
Sources/SeamCarvingApple/        CGImage compatibility facade
Sources/SeamCarvingVision/      Vision face-protection adapter
Sources/SeamCarvingCLI/         CLI options, I/O, batching, artifacts
Sources/seamcarve-cli/          executable entry point
Apps/SeamCarvingApp/            shared SwiftUI editor and acceptance tests
docs/                           Markdown records and GitHub Pages HTML
```
