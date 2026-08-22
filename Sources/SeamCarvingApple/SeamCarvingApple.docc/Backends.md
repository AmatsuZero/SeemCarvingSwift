# ``SeamCarvingApple``

`AppleSeamCarver` bridges Core Graphics, Core Image, Core Video, UIKit, and
AppKit images into the Core canonical representation. Select `.cpu`,
`.accelerate`, `.metal`, or `.automatic`; deterministic mode forces the CPU
reference backend. Metal work is asynchronous and does not synchronously wait
on the main actor.

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
