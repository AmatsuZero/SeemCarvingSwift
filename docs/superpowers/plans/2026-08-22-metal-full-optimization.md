# Metal Full Pipeline Optimization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use the iPad measurements to reduce the Metal full backend's horizontal-seam overhead without changing exact CPU parity or fallback semantics.

**Architecture:** Keep Metal full as the preferred explicit/automatic backend for supported shrink requests. First move horizontal transposition and its masks from CPU loops to the existing Metal transpose kernels, while retaining CPU seam editing and readback boundaries as a safe intermediate step. Only after parity and device measurements validate that change should the agent consider persistent GPU image buffers; enlargement, adaptive ordering, and parallel DP reduction remain out of scope.

**Tech Stack:** Swift 6, Swift Package Manager, Metal, Metal Shading Language, XCTest, XcodeGen, iPadOS 17+.

**Spec:** `docs/superpowers/plans/2026-08-21-seam-carving-swift-implementation.md` and the measured device results recorded below.

## Global Constraints

- Preserve exact sequential seam semantics and CPU/Metal pixel parity.
- Preserve CPU fallback for enlargement and `adaptiveNormalizedCost`.
- Do not change public API names or Metal execution-mode semantics.
- Validate on both macOS Metal tests and the connected iPad.
- Do not optimize based only on M1 Mac results; iPad measurements are the production signal.

## Baseline Evidence

The connected iPad screening test used a 1280x720 deterministic image, direct resize,
one sample per case, and 8-seam removal for the orientation split.

### Combined width-and-height shrink, 1280x720

| Energy / seams | CPU | Accelerate | Metal hybrid | Metal full |
|---|---:|---:|---:|---:|
| backward / 1 | 2512 ms | 2114 ms | 1579 ms | **449 ms** |
| backward / 8 | 19783 ms | 16718 ms | 12466 ms | **3508 ms** |
| forward / 1 | 1162 ms | 1161 ms | 1210 ms | **450 ms** |
| forward / 8 | 9208 ms | 9198 ms | 9615 ms | **3540 ms** |

### Orientation split, 1280x720, 8 seams

| Orientation / energy | CPU | Accelerate | Metal hybrid | Metal full |
|---|---:|---:|---:|---:|
| vertical / backward | 8343 ms | 6772 ms | 4628 ms | **45 ms** |
| vertical / forward | 3147 ms | 3141 ms | 3168 ms | **59 ms** |
| horizontal / backward | 11608 ms | 10060 ms | 7963 ms | **3514 ms** |
| horizontal / forward | 6130 ms | 6129 ms | 6514 ms | **3532 ms** |

The vertical/full result is already highly accelerated; the horizontal/full result
is roughly 60x slower than vertical/full and is the next high-value target. This
isolates CPU transpose/edit orchestration as the first optimization target.

---

### Task 1: Preserve the iPad orientation benchmark as the regression gate

**Files:**
- Modify: `Tests/SeamCarvingMetalTests/PerformanceTests.swift`
- Modify: `Apps/SeamCarvingTestHost/project.yml` only if the test dependencies change
- Test: `Tests/SeamCarvingMetalTests/MetalParityTests.swift`

- [ ] **Step 1: Keep the two device screening tests bounded**

Keep the direct-resize screening at 1280x720 with seam counts `[1, 8]`, and keep
the orientation test at 1280x720 with seam count `8`. The tests must print a
case counter and elapsed milliseconds, but must not use `BackendTimingRecorder`
until the device crash is separately diagnosed.

- [ ] **Step 2: Run the current device gate**

Run:

```bash
xcodebuild -project Apps/SeamCarvingTestHost/SeamCarvingTestHost.xcodeproj \
  -scheme SeamCarvingDeviceTests \
  -destination 'id=00008122-0009185E26DA801C' test \
  -only-testing:SeamCarvingMetalDeviceTests/PerformanceTests/testDeviceOrientationScreening \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=TCU9L9SQC4 \
  CODE_SIGN_IDENTITY='iPhone Developer'
```

Expected: 1 XCTest passes and 16 timing lines are printed.

- [ ] **Step 3: Commit the benchmark gate**

```bash
git add Tests/SeamCarvingMetalTests/PerformanceTests.swift Apps/SeamCarvingTestHost/project.yml Package.swift
git commit -m "test: add iPad orientation benchmark"
```

### Task 2: Move horizontal transpose to Metal

**Files:**
- Modify: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Modify: `Sources/SeamCarvingMetal/Shaders/SeamCarving.metal`
- Test: `Tests/SeamCarvingMetalTests/MetalKernelTests.swift`
- Test: `Tests/SeamCarvingMetalTests/MetalParityTests.swift`

**Interfaces:**
- Reuse the existing `transposeRGBA` and `transposeMask` kernels.
- Add private helpers with the shape `async throws -> RGBA8Image` and `async throws -> Mask` only if the current helper signatures cannot be reused.
- Keep `SeamCarvingBackend.findSeam` and `resize` signatures unchanged.

- [ ] **Step 1: Add kernel parity coverage for device-sized non-square buffers**

Extend `MetalKernelTests` with a non-square RGBA fixture, for example 17x11, and
assert that Metal transpose pixels equal `SeamEditor.transpose(image).pixels`.
Add the equivalent Mask assertion. Do not change the kernel indexing formula
until this test fails on the current implementation.

- [ ] **Step 2: Implement GPU-backed transpose helpers**

Upload the image or mask once, dispatch the existing transpose kernel using the
source dimensions, wait for completion through the existing `submit` helper,
and read back exactly `source.height * source.width * elementSize` bytes. Validate
the output dimensions using `SeamEditor.transpose` semantics.

- [ ] **Step 3: Replace CPU transpose only in the Metal horizontal path**

In `MetalBackend.findSeam` and the horizontal branch of `resize`, replace the
CPU `SeamEditor.transpose` calls for RGBA and Mask data with the new helpers.
Keep seam removal and final CPU image representation unchanged in this task.
Do not change enlargement or adaptive fallback branches.

- [ ] **Step 4: Verify parity on macOS**

Run:

```bash
swift test --package-path . --filter 'MetalKernelTests|MetalParityTests' --parallel
```

Expected: all existing tests plus the new transpose tests pass with exact pixel
and seam parity.

- [ ] **Step 5: Verify orientation timing on iPad**

Run the Task 1 device command and compare horizontal/full against the baseline.
The change is acceptable only if horizontal/full improves without making
vertical/full or exact parity regress.

- [ ] **Step 6: Commit the isolated transpose optimization**

```bash
git add Sources/SeamCarvingMetal/MetalBackend.swift Sources/SeamCarvingMetal/Shaders/SeamCarving.metal Tests/SeamCarvingMetalTests
git commit -m "perf: accelerate Metal horizontal transpose"
```

### Task 3: Decide whether persistent GPU buffers are justified

**Files:**
- Inspect: `Sources/SeamCarvingMetal/MetalBackend.swift`
- Inspect: `Sources/SeamCarvingMetal/Shaders/SeamCarving.metal`
- Measure: `Tests/SeamCarvingMetalTests/PerformanceTests.swift`

- [ ] **Step 1: Compare post-transpose timing components**

Use the orientation test and the existing direct timing to determine whether
horizontal/full remains materially slower than vertical/full after Task 2. Do
not infer this from total combined resize time.

- [ ] **Step 2: Choose the next path using this threshold**

If horizontal/full is within 3x of vertical/full, stop GPU pipeline work and
retain the simpler readback architecture. If it remains above 3x, design a
persistent GPU image/mask buffer path that keeps buffers alive across sequential
seams and reads back only seam coordinates plus the final image.

- [ ] **Step 3: Do not start unrelated Metal work**

Do not implement enlargement, adaptive ordering, or parallel final-row reduction
unless a new benchmark demonstrates that they are user-visible bottlenecks after
horizontal transpose optimization.

### Task 4: Re-run the production decision matrix

**Files:**
- Modify: `Benchmarks/README.md` with the final iPad result and command
- Test: iPad device screening and M1 Mac release benchmark

- [ ] **Step 1: Run release-sized vertical and horizontal cases on iPad**

Use 1920x1080 only after the 1280x720 gate is stable. Use one seam count at a
time and cap iterations at 3 to prevent hour-long runs.

- [ ] **Step 2: Compare Metal full against Accelerate**

Keep Metal as `.automatic` default if iPad Metal full remains at least 15% faster
for the supported shrink buckets and parity remains exact. If not, retain Metal
as explicit-only for the affected bucket.

- [ ] **Step 3: Record the decision**

Update `Benchmarks/README.md` with device model, OS, dimensions, orientation,
energy mode, iterations, and the chosen backend policy. Do not commit raw result
files.

## Review Checklist

- [ ] iPad orientation benchmark passes with 16 timing lines.
- [ ] Mac Metal kernel and parity tests pass.
- [ ] Horizontal Metal path preserves exact CPU pixels and seams.
- [ ] Enlargement and adaptive ordering still use the CPU reference backend.
- [ ] No raw benchmark JSON or generated Xcode project is committed.
- [ ] The executing agent reports measured before/after numbers before starting
  any persistent-buffer redesign.
