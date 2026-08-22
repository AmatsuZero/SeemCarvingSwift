# Benchmarks

Repeatable seam-carving benchmarks. Fixtures are generated deterministically at
runtime (seeded gradients/noise and synthetic protected regions); no copyrighted
images enter the repository.

## Running

```bash
swift run -c release seamcarve-benchmark \
  --sizes 256x256,1920x1080,3840x2160,2048x512,512x2048 \
  --seams 1,8,32,10%,25% \
  --energies backward,forward \
  --backends cpu,accelerate,metal-hybrid,metal-full \
  --warmup 3 \
  --iterations 10 \
  --output /tmp/seam-carving-benchmark.json
```

## Methodology

- Run in **Release** configuration with warmed pipelines.
- Shader runtime compilation (cached per process) is excluded from steady-state
  samples; decode/bridge timing is reported separately as `bridgeNS`.
- Percentiles use fixed nearest-rank: `p50 = ceil(0.50*n)-1`, `p95 = ceil(0.95*n)-1`
  over sorted raw samples.
- Backend parity is checked before any timing sample is accepted.
- Real-device results are required for the physical-device release gate; local
  numbers are not machine-specific and should not be committed.

## `.automatic` policy rule

`.automatic` currently tries Metal, then Accelerate, and finally CPU. The Metal
backend is intentionally partial: shrink requests use its GPU path where
supported, while enlargement and adaptive dimension ordering use the CPU
reference path. Any change to this policy must be based on parity-checked
Release measurements from both an iPhone/iPad and an Apple-silicon Mac.

Before making Metal the preferred production path for a request-size bucket,
Metal must show at least 15% lower p50 than Accelerate without worsening p95
peak scratch by more than 10%. Record vertical and horizontal shrink separately;
horizontal results include GPU transpose overhead (the Metal horizontal path
transposes RGBA and mask buffers on the GPU via the `transposeRGBA` /
`transposeMask` kernels) and should not be inferred from vertical-only
measurements.

## Production decision matrix (iPad, 2026-08-22)

Device: iPad (id `00008122-0009185E26DA801C`), iPadOS 17+. One sample per case,
direct resize, deterministic seeded image, 1280x720, 8-seam removal.

### Orientation split

| Orientation / energy | CPU | Accelerate | Metal hybrid | Metal full |
|---|---:|---:|---:|---:|
| vertical / backward | 8347 ms | 6811 ms | 4673 ms | **44 ms** |
| vertical / forward | 3121 ms | 3132 ms | 3133 ms | **55 ms** |
| horizontal / backward | 11719 ms | 10182 ms | 4649 ms | **69 ms** |
| horizontal / forward | 6135 ms | 6130 ms | 3116 ms | **86 ms** |

### Decision

- Horizontal Metal full dropped from ~3514 ms (CPU transpose) to ~69 ms after
  the GPU transpose optimization, bringing it to ~1.6x of vertical Metal full
  (well within the 3x stop threshold). No persistent GPU buffer redesign,
  enlargement, adaptive ordering, or parallel final-row reduction is warranted.
- Metal full is >100x faster than Accelerate for both orientations at this size
  with exact CPU/Metal pixel and seam parity (verified on macOS). The 15%
  threshold is exceeded by a wide margin, so Metal remains the preferred
  production path for supported shrink requests (vertical and horizontal).
- Enlargement and `.adaptiveNormalizedCost` ordering still delegate to the CPU
  reference backend, preserving package-wide semantics.

Command:

```bash
xcodebuild -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj \
  -scheme SeamCarvingDeviceTests \
  -destination 'id=00008122-0009185E26DA801C' test \
  -only-testing:SeamCarvingMetalDeviceTests/PerformanceTests/testDeviceOrientationScreening \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=TCU9L9SQC4 \
  CODE_SIGN_IDENTITY='iPhone Developer'
```
