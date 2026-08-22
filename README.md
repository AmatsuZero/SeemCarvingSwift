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

## Scope and limitations

The package does not provide video temporal coherence, learned saliency,
transport maps, approximate multi-seam batches, HDR/extended-range input,
MLX, Core ML, or conventional Lanczos pre-scaling. Exact sequential seam
semantics are the default. Caire is reference material only; `.caireInspired`
is not equivalent to Caire. The Vision module is optional and never imported by
Core. A project license is intentionally not selected by this plan.

Metal is an optional, asynchronous acceleration backend for shrink requests.
Its full path accelerates energy, dynamic programming, and vertical seam
editing, while horizontal edits still use CPU transposition. Enlargement and
adaptive dimension ordering intentionally use the CPU reference backend to
preserve package-wide semantics. `.automatic` tries Metal first, then
Accelerate, and finally CPU; use `.deterministic` or `.cpu` when reproducible
reference behavior is required.

Run the tests with `swift test`. See `Benchmarks/README.md` for reproducible
Release measurements and the explicit rule for changing `.automatic` policy.
