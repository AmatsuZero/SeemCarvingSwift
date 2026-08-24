# ``SeamCarvingApple``

This v2 compatibility facade re-exports `SeamCarvingAppleRuntime` and
`SeamCarvingAppleImaging`, preserving the CGImage-based API:

```swift
import SeamCarvingCore
import SeamCarvingApple

let carver = try AppleSeamCarver()
let output = try await carver.resize(cgImage, toPixelSize: target)
```

`UIImage` and `NSImage` are intentionally not re-exported because they belong
to mutually exclusive framework adapters. Import their product explicitly:

```swift
// iOS, iPadOS, and Mac Catalyst
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingUIKit

// macOS
import SeamCarvingCore
import SeamCarvingAppleRuntime
import SeamCarvingAppKit
```

`AppleSeamCarver` selects `.cpu`, `.accelerate`, `.metal`, or `.automatic`;
deterministic mode forces the CPU reference backend. Metal work is asynchronous
and does not synchronously wait on the main actor. CGImage and Core Image
bridges live in `SeamCarvingAppleImaging`; CVPixelBuffer has the separate
`SeamCarvingCoreVideo` adapter.

HDR and extended-range inputs are rejected rather than silently tone-mapped.

In `.automatic` mode, the factory tries Metal first, then Accelerate, and finally
the CPU reference backend. Deterministic mode always selects the CPU backend.

Metal currently accelerates the supported shrink path. Its full mode keeps
energy, dynamic programming, and vertical seam editing on the GPU, but the
horizontal path uses CPU transposition and enlargement or adaptive dimension
ordering intentionally falls back to the CPU reference backend. This preserves
the package's exact sequential semantics while leaving the faster path opt-in
for callers that explicitly select Metal.

## Frozen public contract

The public contract for this module is now frozen per the capability matrix
(`docs/capability-matrix.md`). Backend and deterministic selection is a visible,
explainable user choice: callers pick `.cpu`, `.accelerate`, `.metal`, or
`.automatic` and may set `deterministic` to force the CPU reference backend.
The GUI must surface these choices rather than hide them. No public API changes
accompany this freeze; new capability (e.g. opt-in pre-scale) is introduced in a
later task.
