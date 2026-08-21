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
