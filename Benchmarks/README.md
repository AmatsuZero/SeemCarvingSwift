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

`.automatic` currently selects Accelerate with CPU as its only fallback. To change
the default to Metal, both an iPhone and an Apple-silicon Mac must show Metal at
least 15% lower p50 than Accelerate, without worsening p95 peak scratch by more
than 10% for the affected request-size bucket.
