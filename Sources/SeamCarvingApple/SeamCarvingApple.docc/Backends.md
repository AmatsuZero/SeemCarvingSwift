# ``SeamCarvingApple``

`AppleSeamCarver` bridges Core Graphics, Core Image, Core Video, UIKit, and
AppKit images into the Core canonical representation. Select `.cpu`,
`.accelerate`, `.metal`, or `.automatic`; deterministic mode forces the CPU
reference backend. Metal work is asynchronous and does not synchronously wait
on the main actor.

HDR and extended-range inputs are rejected rather than silently tone-mapped.

In `.automatic` mode, the factory tries Metal first, then Accelerate, and finally
the CPU reference backend. Deterministic mode always selects the CPU backend.
