# ``SeamCarvingCore``

Use the Core module for deterministic, platform-independent seam carving over
`RGBA8Image` values. Construct a valid image, choose a `PixelSize`, and await
`SeamCarver.resize(_:to:options:)`.

The public API supports exact shrinking and enlargement, backward Sobel and
forward-luma energy, masks, cancellation, and progress. Images are canonical
upright RGBA8; platform-specific decoding belongs to `SeamCarvingApple`.

Backend SPI declarations are implementation contracts and are not supported
for ordinary application code.
