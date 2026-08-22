# ``SeamCarvingVision``

This optional target adapts Vision face observations into Core masks. Callers
must choose an explicit face request revision. `.caireInspired` and
`.visionQuality` are distinct raster policies, and detection can run once or
be repeated for each resize pass. Face protection and removal masks are
composed in canonical upright pixel coordinates; protection wins on overlap.
