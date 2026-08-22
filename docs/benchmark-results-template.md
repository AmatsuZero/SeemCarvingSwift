# Benchmark Results

Status: **pending physical-device release gate**

Local Mac verification (2026-08-22): M1 MacBookPro18,1, macOS 26.6.2,
Metal API/GPU Validation passed in the iOS Simulator. SwiftPM Core TSan (50
tests) and the Xcode-built Core/Metal test bundles (50 + 9 tests) passed when
the Xcode TSan runtime was preloaded with `DYLD_INSERT_LIBRARIES`. The normal
`xcodebuild ENABLE_THREAD_SANITIZER=YES test` wrapper aborts before test
bootstrap on this environment; retain the manual bundle command as the local
TSan evidence.

| Field | Value |
|---|---|
| Device model / UDID suffix | |
| OS / Xcode / Swift | |
| Git commit | |
| Vision request revision | |
| Backend / mode | |
| Benchmark JSON attachment | |
| Date / operator | |

Record p50/p95 for every phase (`bridge`, `energy`, `mask`, `dynamicProgramming`,
`backtrack`, `edit`, `commandEncoding`, `gpuWait`, `total`) and peak scratch
bytes for each size/seam/energy bucket. Attach Metal validation logs or a
screenshot. A physical iPhone/iPad run, GPU validation capture, Thread
Sanitizer run, and full Release matrix are external gates and must not be
marked passed without device evidence.
