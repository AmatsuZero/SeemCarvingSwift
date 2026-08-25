# WebGPU-first browser backend design

## Status

Proposed and user-approved direction. This document defines the implementation
scope before code changes. The user chose modern-browser support: WebGPU is the
preferred browser backend and the existing Swift/WASM CPU worker remains the
fallback. WebGL2 is explicitly out of scope for this iteration.

## Goals

1. Accelerate supported seam-carving shrink operations in the browser with
   WebGPU, without changing the browser page-to-worker request/response API.
2. Keep all intermediate GPU data on the GPU and read pixels back only once per
   completed job.
3. Preserve a deterministic, compatible CPU fallback through the current
   Swift/WASM `WasmBridgeCore` implementation.
4. Make actual backend selection observable and testable.
5. Establish browser tests for GPU selection, fallback, and output parity on
   small deterministic images.

## Non-goals

- WebGL/WebGL2 implementation or fallback.
- Changing the root Swift package's platform/dependency boundaries.
- General browser image I/O, progress reporting, cooperative cancellation, or
  multi-threaded WASM.
- First-iteration support for enlargement, adaptive dimension order, masks,
  forward energy, or horizontal seams. These use the existing WASM CPU fallback.

## Supported WebGPU operation (MVP)

The GPU backend accepts a `ResizeRequestMessage` only when it is a vertical
shrink (`targetWidth < sourceWidth`, unchanged height) using the existing
backward-Sobel default options. The worker chooses WebGPU if a device can be
acquired and initialized; any unsupported request, unavailable API/device,
device loss, shader/pipeline error, or runtime GPU error runs through the
existing Swift/WASM worker bridge instead. Both paths return the existing
`success` response payload exactly.

This narrow scope isolates the highest-value Metal-like path. Later milestones
can add GPU transpose for horizontal shrink, masks, forward energy, and full
2-D order while retaining the same selector interface.

## Architecture

### Worker-owned backends

`resize.worker.ts` remains the single message boundary and owns a
`ResizeProcessor` abstraction:

- `WebGPUResizeProcessor`: TypeScript host code plus WGSL compute shaders.
- `WasmResizeProcessor`: a thin wrapper around the current `wasmResize` bridge.
- `BrowserResizeSelector`: detects and lazily initializes WebGPU, classifies a
  request's eligibility, then dispatches to GPU or WASM.

No WebGPU API is introduced into Swift. This preserves the checked boundary
where `WasmBridgeCore` imports only `SeamCarvingCore` and prevents JavaScriptKit
GPU lifecycle concerns from entering the core algorithm package.

### GPU buffers and passes

For each eligible job, upload compact RGBA8 input once. Allocate/reuse GPU
buffers for current image, next image, luma, energy, two width-sized DP rows,
a `(width * height)` parent buffer, and seam coordinates. For every seam:

1. Convert current RGBA8 pixels to linear luminance.
2. Calculate Sobel energy.
3. Initialize the first DP row.
4. Encode one DP compute dispatch for each subsequent image row, ping-ponging
   DP rows and recording parent direction values.
5. Reduce the final row, backtrack the seam, and remove it to the alternate
   RGBA8 buffer.
6. Swap current/next image buffers and decrement width.

All steps for the job are encoded before `queue.submit`; no intermediate
`mapAsync`, canvas read, or worker message occurs. Final RGBA8 data alone is
copied to a MAP_READ buffer, mapped, and transferred to the page as it is now.

WGSL uses explicit byte/word layouts and CPU-equivalent edge clamps, luma
coefficients, Sobel formula, floating comparison/tie-breaking, and seam parent
choice. Initial shader workgroup size is 256 for one-dimensional passes and
8x8 for Sobel, then tuned from measurements.

### Result correctness

The CPU/WASM result is the oracle. GPU tests compare dimensions and exact RGBA8
pixels for deterministic fixture cases. If unavoidable cross-adapter floating
point variance appears, tests will first preserve algorithmic tie-breaking and
then explicitly document a bounded numeric policy; the implementation must not
silently substitute perceptual comparison.

## Failure, fallback, and lifecycle

- Feature probe uses `navigator.gpu`; adapter/device creation is lazy.
- A GPU error before result production falls back to WASM for that job and logs
  a diagnostic in development builds only.
- `device.lost` clears cached GPU state; a later job may attempt one fresh
  initialization, otherwise falls back.
- Existing worker termination remains cancellation behavior. No partially
  produced GPU result is posted.
- Requests unsupported by the MVP never initialize WebGPU unnecessarily.

## API and observability

The page protocol remains compatible. Add a non-breaking `backend` field to a
successful worker result (`webgpu` or `wasm-cpu`) and display it in the demo
status for manual verification. Test-only worker hooks may force WebGPU
unavailable/unsupported conditions; production code must not expose a user
switch that bypasses normal fallback policy.

## Test and benchmark plan

1. Unit-test eligibility, fallback classification, byte-layout helpers, and
   output validation in the web test environment.
2. Browser integration tests: existing WASM path, unavailable WebGPU fallback,
   unsupported-request fallback, WebGPU result dimensions/pixels, and no change
   to transferred-buffer ownership.
3. Add a benchmark page/script that reports end-to-end and GPU-only durations
   for fixed generated images/seam counts. Compare a warmed WebGPU run against
   the current Worker/WASM baseline.
4. Run production Vite build and Playwright Chromium tests; manually check
   Safari and Edge before release.

## Acceptance criteria

- Eligible vertical shrink succeeds through WebGPU in a supporting modern
  browser and returns the same result shape and pixels as CPU for covered
  fixtures.
- Unavailable, lost, failed, and unsupported GPU cases successfully use WASM
  without API changes or page hangs.
- Existing WASM boundary check, web build, and all browser tests pass.
- Measurements demonstrate an end-to-end benefit for at least one realistic
  large-image/seam-count bucket; if they do not, retain the selector/fallback
  work but do not claim a performance improvement.

## Rollout order

1. Selector/protocol/observability and tests, preserving WASM behavior.
2. WebGPU vertical backward-Sobel shrink implementation with CPU parity tests.
3. Benchmarks and workgroup/buffer tuning.
4. Only after measured success: horizontal shrink via GPU transpose, then other
   modes. WebGL2 remains a separately approved future project.
