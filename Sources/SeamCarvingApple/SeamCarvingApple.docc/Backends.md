# ``SeamCarvingApple``

`AppleSeamCarver` bridges Core Graphics, Core Image, Core Video, UIKit, and
AppKit images into the Core canonical representation. Select `.cpu`,
`.accelerate`, `.metal`, or `.automatic`; deterministic mode forces the CPU
reference backend. Metal work is asynchronous and does not synchronously wait
on the main actor.

HDR and extended-range inputs are rejected rather than silently tone-mapped.
