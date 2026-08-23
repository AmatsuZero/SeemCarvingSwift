# SeamCarvingSwift

SeamCarvingSwift is a Swift 6 package for deterministic content-aware resizing
on iOS 17+ and macOS 14+. The Core module is platform-independent and operates
on upright, origin-zero, straight-alpha RGBA8 images.

## Quick start

```swift
import SeamCarvingCore

let image = try RGBA8Image(width: 4, height: 4, pixels: pixels)
let target = try PixelSize(width: 3, height: 4)
let resized = try await SeamCarver().resize(image, to: target)
```

`SeamCarver` supports shrink and enlargement, backward Sobel or forward-luma
energy, protection/removal masks, cancellation, progress callbacks, and
explicit CPU/Accelerate/Metal selection through the Apple facade. `CGImage`,
`CIImage`, `CVPixelBuffer`, `UIImage`, and `NSImage` bridges normalize input
before carving and restore the requested platform representation.

```swift
let carver = try AppleSeamCarver(configuration: .init(backend: .automatic))
let output = try await carver.resize(inputCGImage, toPixelSize: target)
```

For object removal, provide a removal mask and optionally request restoration
of the removed width. Protection has precedence over removal. Vision face
protection is an optional adapter: choose an explicit Vision request revision,
`.caireInspired` or `.visionQuality`, and `.detectOnce` or `.redetectEachPass`.
All face rectangles use the same upright canonical coordinates as Core masks.


## Command-line tool

`seamcarve-cli` uses Apple `swift-argument-parser` for argv syntax while
keeping `CLIOptions` and `CLIConfiguration` as the business configuration
layer. The argv-to-options seam remains available as `CLIOptions.parse(_:)` for
unit tests and embedders.

```bash
seamcarve-cli INPUT OUTPUT (--width PIXELS --height PIXELS | --percentage P | --square) [options]
seamcarve-cli --input-dir DIR --output-dir DIR (--width PIXELS --height PIXELS | --percentage P | --square) [options]
```

Inputs can be local paths, `http(s)` URLs, or `-` for stdin. Outputs can be
local paths or `-` for binary stdout; in stdout mode summaries stay off stdout
so image bytes are not polluted. Supported options include backend/energy/order
selection, masks, face protection, `--format png|jpeg|bmp`, debug seam artifacts,
and batch `--recursive`/`--concurrency`.

## Capability alignment

The package's user-facing capabilities are tracked against a Caire-inspired
checklist in [`docs/capability-matrix.md`](docs/capability-matrix.md). That
document classifies each capability as existing, requiring API exposure, or
requiring new implementation, and freezes the public product contract — the
GUI only consumes the existing `ResizeOptions` (energy mode, dimension order,
masks, progress) and `AppleSeamCarver` facade; no new library APIs are needed
for the current capability set.

## Scope and limitations

The package does not provide video temporal coherence, learned saliency,
transport maps, approximate multi-seam batches, HDR/extended-range input,
MLX, or Core ML. Conventional automatic Lanczos pre-scaling is NOT performed:
exact sequential seam semantics are the default and the `none` pre-scale
strategy never pre-scales implicitly. An explicit, opt-in
`.lanczosThenExactResidual` pre-scale strategy IS available
(`ResizeOptions.preScaleStrategy`); it Lanczos-scales the image and every
protection/removal mask to an intermediate size before the residual seam
carving reaches the exact target dimensions. This is an approximation and is
Apple-platform only (it requires Core Image). Caire is reference material only;
`.caireInspired` is not equivalent to Caire. The Vision module is optional and
never imported by Core. A project license is intentionally not selected by this
plan.

Metal is an optional, asynchronous acceleration backend for shrink requests.
Its full path accelerates energy, dynamic programming, and vertical seam
editing, while horizontal edits still use CPU transposition. Enlargement and
adaptive dimension ordering intentionally use the CPU reference backend to
preserve package-wide semantics. `.automatic` tries Metal first, then
Accelerate, and finally CPU; use `.deterministic` or `.cpu` when reproducible
reference behavior is required.

Run the tests with `swift test`. See `Benchmarks/README.md` for reproducible
Release measurements and the explicit rule for changing `.automatic` policy.
