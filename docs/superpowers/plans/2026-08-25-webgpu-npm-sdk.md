# WebGPU-first npm SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish `@seemcarving/wasm`, a browser SDK with a WebGPU-first vertical-shrink backend and a compatible Swift/WASM CPU fallback.

**Architecture:** Keep `SeamCarvingCore` and `WasmBridgeCore` CPU-only. A standalone TypeScript package owns the public API, module Worker, backend selector, WGSL shaders, GPU resources, and generated JavaScriptKit assets. The demo is a Vite consumer of that package; the Worker chooses WebGPU only for MVP-eligible requests and calls an exported Swift/WASM CPU function for every fallback.

**Tech Stack:** Swift 6.3.3 WASM SDK, JavaScriptKit 0.56.1, TypeScript 5.9.2, WebGPU/WGSL, Vite 7.1.7, Vitest 3.2.x, Playwright 1.55.0, npm 11.6.2, GitHub Actions, npm Trusted Publishing OIDC.

**Spec:** `docs/superpowers/specs/2026-08-25-webgpu-browser-backend-design.md`

## Global Constraints

- Do not add a root `package.json`; the root remains a Swift Package.
- Publish exactly `@seemcarving/wasm` as ESM with generated `.d.ts` and all WASM/runtime assets in the tarball.
- The package must work in modern browsers; WebGPU is preferred, while WASM CPU is mandatory fallback.
- MVP GPU support is only vertical shrink (`targetWidth < sourceWidth`, identical height), backward-Sobel energy, no masks, no forward-energy, no enlargement, and no horizontal operation.
- GPU code is TypeScript + WGSL only; no WebGPU import or lifecycle code enters `SeamCarvingCore` or `WasmBridgeCore`.
- Preserve compact top-left-origin straight-alpha RGBA8 inputs/outputs, the 2,000,000-pixel limit, and 80,000,000 pixel-work limit.
- Do not read/map intermediate GPU buffers; map final RGBA8 bytes exactly once per successful job.
- All changes are TDD: make a focused test fail, implement the smallest code to pass it, then run its focused command.
- Publish only from a `wasm-v*` tag using npm Trusted Publishing OIDC; do not introduce `NPM_TOKEN`.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `Packages/SeamCarvingWasm/package.json` | Public package identity, ESM export map, files allow-list, scripts, engine floor. |
| `Packages/SeamCarvingWasm/tsconfig.json` | Strict declaration-producing TypeScript settings. |
| `Packages/SeamCarvingWasm/vite.config.ts` | Library/Worker/WASM asset build configuration. |
| `Packages/SeamCarvingWasm/src/index.ts` | Public `createSeamCarver` API and exported request/result types only. |
| `Packages/SeamCarvingWasm/src/client.ts` | Main-thread Worker client, transfer/cancellation/lifecycle state. |
| `Packages/SeamCarvingWasm/src/protocol.ts` | Internal validated request/response and `BackendIdentifier` contract. |
| `Packages/SeamCarvingWasm/src/worker.ts` | Worker entry: validates messages, calls selector, posts transferable result. |
| `Packages/SeamCarvingWasm/src/wasm-cpu.ts` | JavaScriptKit initialization and call to the Swift-exported CPU function. |
| `Packages/SeamCarvingWasm/src/selector.ts` | Eligibility rules, lazy GPU initialization, device-loss reset, fallback policy. |
| `Packages/SeamCarvingWasm/src/webgpu.ts` | GPU buffers, command encoding, final readback, no public API. |
| `Packages/SeamCarvingWasm/src/shaders.ts` | WGSL source strings for luma, Sobel, DP, reduce, backtrack, remove. |
| `Packages/SeamCarvingWasm/tests/*.spec.ts` | Package unit/browser tests and packed-consumer test harness. |
| `Packages/SeamCarvingWasm/scripts/stage-wasm.mjs` | Copies generated JavaScriptKit PackageToJS tree into package source assets. |
| `Examples/WasmDemo/scripts/build-swift.sh` | Builds Swift artifact then calls package asset staging rather than copying into app source. |
| `Examples/WasmDemo/swift/Sources/WasmBridgeWorker/main.swift` | Exposes `__seamCarvingWasmResize` callable; Swift no longer owns Worker `onmessage`. |
| `Examples/WasmDemo/web/*` | Vite sample app consuming `@seemcarving/wasm` via local `file:` dependency. |
| `.github/workflows/wasm-demo.yml` | Package, packed-consumer, demo, multi-browser CI checks. |
| `.github/workflows/publish-npm.yml` | Tag-only OIDC rebuild, validation, and npm publication. |

## Task 1: Extract the Swift CPU callable boundary

**Files:**
- Modify: `Examples/WasmDemo/swift/Sources/WasmBridgeWorker/main.swift`
- Modify: `Examples/WasmDemo/scripts/check-wasm-boundaries.sh`
- Test: `Examples/WasmDemo/swift/Tests/WasmBridgeCoreTests/WasmBridgeCoreTests.swift`
- Test: `Examples/WasmDemo/web/tests/worker-protocol.spec.ts`

**Interfaces:**
- Produces global callable `globalThis.__seamCarvingWasmResize(request): Promise<ResizeResponseMessage>`.
- Consumes the existing `ResizeRGBA8Request`, `resizeRGBA8(_:)`, and `ResizeRGBA8Response`.
- Removes Swift ownership of `globalThis.onmessage`; later TypeScript Worker code is the sole message dispatcher.

- [ ] **Step 1: Add a failing browser test proving a valid request receives `backend: "wasm-cpu"` from the CPU path.**

```ts
const response = await window.__testResizeRGBA8!(pixels, 2, 1, 1, 1);
expect(response).toMatchObject({ type: "success", backend: "wasm-cpu", width: 1, height: 1 });
```

- [ ] **Step 2: Run the focused test and verify it fails because `backend` and the new dispatcher do not exist.**

Run: `cd Examples/WasmDemo/web && npx playwright test tests/worker-protocol.spec.ts -g 'CPU path' --project=chromium`

Expected: FAIL because the current Swift-owned `onmessage` success object has no `backend` field.

- [ ] **Step 3: Refactor `main.swift` so parsing and conversion are callable, not message-owned.**

```swift
let wasmResize = JSClosure { arguments in
    guard let request = arguments.first, let parsed = request(from: request) else {
        return .promiseRejected(JSValue.string("Invalid resize request"))
    }
    return .promise { resolve, reject in
        Task { @MainActor in
            do { resolve(postableSuccess(try await resizeRGBA8(parsed.request), jobId: parsed.jobId)) }
            catch { reject(JSValue.string(String(describing: error))) }
        }
    }
}
JSObject.global.__seamCarvingWasmResize = .object(wasmResize)
```

Keep the same byte/dimension validation and use transferable `ArrayBuffer` output. Emit only a `ready` message during initialization; TypeScript attaches `onmessage` after `init()` resolves.

- [ ] **Step 4: Update the protocol type in the later package task’s source layout and make the temporary demo protocol accept `backend: "wasm-cpu"`.**

```ts
export type BackendIdentifier = "wasm-cpu" | "webgpu";
export interface ResizeSuccessMessage { type: "success"; backend: BackendIdentifier; /* existing fields */ }
```

- [ ] **Step 5: Run Swift bridge tests, boundary check, and focused browser test.**

Run: `swift test --package-path Examples/WasmDemo/swift --filter WasmBridgeCoreTests && bash Examples/WasmDemo/scripts/check-wasm-boundaries.sh && cd Examples/WasmDemo/web && npx playwright test tests/worker-protocol.spec.ts -g 'CPU path' --project=chromium`

Expected: PASS.

- [ ] **Step 6: Commit the isolated bridge refactor.**

```bash
git add Examples/WasmDemo/swift Examples/WasmDemo/scripts/check-wasm-boundaries.sh Examples/WasmDemo/web/tests/worker-protocol.spec.ts
git commit -m "refactor: expose WASM CPU resize callable"
```

## Task 2: Create the standalone publishable package and stage WASM assets

**Files:**
- Create: `Packages/SeamCarvingWasm/package.json`
- Create: `Packages/SeamCarvingWasm/tsconfig.json`
- Create: `Packages/SeamCarvingWasm/vite.config.ts`
- Create: `Packages/SeamCarvingWasm/scripts/stage-wasm.mjs`
- Create: `Packages/SeamCarvingWasm/src/index.ts`
- Create: `Packages/SeamCarvingWasm/src/protocol.ts`
- Create: `Packages/SeamCarvingWasm/README.md`
- Modify: `Examples/WasmDemo/scripts/build-swift.sh`
- Modify: `.gitignore`
- Test: `Packages/SeamCarvingWasm/tests/package-contents.spec.mjs`

**Interfaces:**
- Produces package `@seemcarving/wasm` with `exports["."].types`, `exports["."].import`, and `exports["./worker"]`.
- Produces `npm run build`, `npm run test:pack`, and a staged `src/generated/` tree.
- Consumes PackageToJS output at `Examples/WasmDemo/swift/.build/plugins/PackageToJS/outputs/Package`.

- [ ] **Step 1: Write a failing package-content test that packs the package and asserts required files.**

```js
const { filename } = JSON.parse(execFileSync("npm", ["pack", "--json"], { cwd: packageDir }))[0];
const files = execFileSync("tar", ["-tf", filename], { cwd: packageDir, encoding: "utf8" });
for (const name of ["package/dist/index.js", "package/dist/worker.js", "package/dist/WasmBridgeWorker.wasm", "package/dist/index.d.ts"]) {
  assert.match(files, new RegExp(`^${name}$`, "m"));
}
```

- [ ] **Step 2: Run it and verify it fails because the package directory does not exist.**

Run: `node --test Packages/SeamCarvingWasm/tests/package-contents.spec.mjs`

Expected: FAIL with missing package directory.

- [ ] **Step 3: Add package metadata and deterministic asset staging.**

```json
{
  "name": "@seemcarving/wasm",
  "version": "0.1.0",
  "type": "module",
  "exports": { ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" }, "./worker": "./dist/worker.js" },
  "files": ["dist", "README.md", "LICENSE"],
  "publishConfig": { "access": "public", "registry": "https://registry.npmjs.org" }
}
```

Make `stage-wasm.mjs` delete `src/generated`, copy the PackageToJS tree recursively, and throw if `index.js` or any `.wasm` file is absent. Change `build-swift.sh` to run this script after Swift output validation. Ignore `Packages/SeamCarvingWasm/src/generated/`, `dist/`, `node_modules/`, and packed tarballs.

- [ ] **Step 4: Implement the initial typed public surface with a deliberate throw until the Worker client lands.**

```ts
export type BackendIdentifier = "wasm-cpu" | "webgpu";
export interface ResizeRequest { pixels: Uint8Array; width: number; height: number; targetWidth: number; targetHeight: number; }
export interface ResizeResult { pixels: Uint8Array; width: number; height: number; backend: BackendIdentifier; }
export interface SeamCarver { resize(request: ResizeRequest): Promise<ResizeResult>; terminate(): void; }
export async function createSeamCarver(): Promise<SeamCarver> { throw new Error("Worker client not installed"); }
```

Add `vitest@3.2.x` and `test:unit: vitest run` to the package dev dependencies. Configure Vite library mode to preserve Worker/WASM URL assets and emit declarations with `tsc --emitDeclarationOnly` before Vite bundling.

- [ ] **Step 5: Build Swift generated assets, install package dependencies, run the pack test, and verify it passes.**

Run: `Examples/WasmDemo/scripts/build-swift.sh && npm ci --prefix Packages/SeamCarvingWasm && npm run build --prefix Packages/SeamCarvingWasm && node --test Packages/SeamCarvingWasm/tests/package-contents.spec.mjs`

Expected: PASS; the tarball contains only allow-listed publish files and all runtime assets.

- [ ] **Step 6: Commit the package scaffold.**

```bash
git add Packages/SeamCarvingWasm Examples/WasmDemo/scripts/build-swift.sh .gitignore
git commit -m "feat: scaffold publishable WASM SDK"
```

## Task 3: Implement the public Worker client and migrate the demo

**Files:**
- Create: `Packages/SeamCarvingWasm/src/client.ts`
- Create: `Packages/SeamCarvingWasm/src/worker.ts`
- Modify: `Packages/SeamCarvingWasm/src/index.ts`
- Modify: `Examples/WasmDemo/web/package.json`
- Modify: `Examples/WasmDemo/web/src/main.ts`
- Modify: `Examples/WasmDemo/web/tests/worker-protocol.spec.ts`
- Test: `Packages/SeamCarvingWasm/tests/client.spec.ts`

**Interfaces:**
- Consumes `createSeamCarver(options?: { worker?: Worker })` and worker messages from `protocol.ts`.
- Produces a `SeamCarver` that transfers a copied `ArrayBuffer`, rejects concurrent/terminated requests deterministically, and resolves `ResizeResult`.
- Worker initially calls `WasmCPUProcessor.resize` for all valid requests.

- [ ] **Step 1: Write failing tests for the SDK lifecycle.**

```ts
const carver = await createSeamCarver({ worker: fakeWorker });
await expect(carver.resize({ pixels, width: 2, height: 1, targetWidth: 1, targetHeight: 1 }))
  .resolves.toMatchObject({ backend: "wasm-cpu", width: 1, height: 1 });
carver.terminate();
await expect(carver.resize(request)).rejects.toThrow("terminated");
```

- [ ] **Step 2: Run the test and verify it fails because `createSeamCarver` throws.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/client.spec.ts`

Expected: FAIL with `Worker client not installed`.

- [ ] **Step 3: Implement client ownership and the TypeScript-owned Worker dispatcher.**

```ts
export async function createSeamCarver(options: CreateSeamCarverOptions = {}): Promise<SeamCarver> {
  return new WorkerSeamCarver(options.worker ?? new Worker(new URL("./worker.js", import.meta.url), { type: "module" }));
}
```

In `worker.ts`, call generated `init()`, await `__seamCarvingWasmResize`, validate every request before dispatch, then post `success` with transferred output. Retain current terminate-and-recreate cancellation behavior in `WorkerSeamCarver`; remove demo-only Worker client code.

- [ ] **Step 4: Make the Vite demo install the local package and consume only its public API.**

```json
"dependencies": { "@seemcarving/wasm": "file:../../../Packages/SeamCarvingWasm" }
```

Replace `ResizeWorkerClient` and protocol imports in `main.ts` with `createSeamCarver`; retain Canvas decode/export and UI validation. Display `response.backend` in the completion status. Keep test hooks only in the package’s test entry, not the package production API.

- [ ] **Step 5: Run client tests and Chromium demo protocol tests.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/client.spec.ts && cd Examples/WasmDemo/web && npm install && npx playwright test tests/worker-protocol.spec.ts --project=chromium`

Expected: PASS and the demo reports `wasm-cpu`.

- [ ] **Step 6: Commit the SDK client/demo migration.**

```bash
git add Packages/SeamCarvingWasm Examples/WasmDemo/web/package.json Examples/WasmDemo/web/package-lock.json Examples/WasmDemo/web/src/main.ts Examples/WasmDemo/web/tests
git commit -m "feat: expose WASM resize SDK client"
```

## Task 4: Add selector, eligibility, and reliable CPU fallback

**Files:**
- Create: `Packages/SeamCarvingWasm/src/selector.ts`
- Create: `Packages/SeamCarvingWasm/src/wasm-cpu.ts`
- Modify: `Packages/SeamCarvingWasm/src/worker.ts`
- Modify: `Packages/SeamCarvingWasm/src/protocol.ts`
- Test: `Packages/SeamCarvingWasm/tests/selector.spec.ts`

**Interfaces:**
- Produces `isWebGPUEligible(request): boolean` and `ResizeSelector.resize(request): Promise<ResizeResult>`.
- Consumes `GPUProcessor` with `initialize()`/`resize()` and `WasmCPUProcessor.resize()`.
- GPU failure before a result invokes CPU once for the same request; CPU failure returns a worker failure.

- [ ] **Step 1: Write failing selector tests for supported and fallback requests.**

```ts
expect(isWebGPUEligible(req(8, 4, 7, 4))).toBe(true);
expect(isWebGPUEligible(req(8, 4, 8, 3))).toBe(false);
await expect(selector.resize(req(8, 4, 7, 4))).resolves.toMatchObject({ backend: "wasm-cpu" });
expect(wasm.resize).toHaveBeenCalledTimes(1);
```

Use fakes where WebGPU initialization rejects and CPU returns a known result.

- [ ] **Step 2: Run the test and verify it fails because no selector exists.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/selector.spec.ts`

Expected: FAIL with module-not-found.

- [ ] **Step 3: Implement exact MVP classification and device lifecycle.**

```ts
export function isWebGPUEligible(r: ResizeRequestMessage): boolean {
  return r.targetWidth > 0 && r.targetHeight === r.sourceHeight && r.targetWidth < r.sourceWidth;
}
```

Probe `navigator.gpu` lazily only for eligible requests. Cache a successful processor, set it to `undefined` on `device.lost`, and catch initialization/encoding/map failures around the GPU call; route those to CPU without posting a partial GPU result. Do not initialize WebGPU for an ineligible request.

- [ ] **Step 4: Run focused selector tests and the existing WASM fallback browser tests.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/selector.spec.ts && cd Examples/WasmDemo/web && npx playwright test tests/worker-protocol.spec.ts --project=chromium`

Expected: PASS; a no-WebGPU fake still gives the CPU image result.

- [ ] **Step 5: Commit selector and fallback behavior.**

```bash
git add Packages/SeamCarvingWasm
git commit -m "feat: select WebGPU with WASM fallback"
```

## Task 5: Implement GPU energy and one-seam vertical shrink with parity tests

**Files:**
- Create: `Packages/SeamCarvingWasm/src/shaders.ts`
- Create: `Packages/SeamCarvingWasm/src/webgpu.ts`
- Modify: `Packages/SeamCarvingWasm/src/selector.ts`
- Test: `Examples/WasmDemo/web/tests/webgpu-parity.spec.ts`

**Interfaces:**
- Produces `WebGPUProcessor.initialize(): Promise<WebGPUProcessor>` and `resize(request): Promise<ResizeResult>`.
- Consumes eligible `ResizeRequestMessage` and returns exactly `targetWidth * targetHeight * 4` RGBA8 bytes with `backend: "webgpu"`.
- `shaders.ts` exports `rgbaToLumaWGSL`, `sobelWGSL`, `initializeDPWGSL`, `accumulateDPWGSL`, `reduceWGSL`, `backtrackWGSL`, and `removeVerticalWGSL`.

- [ ] **Step 1: Write a failing Chromium parity test for a deterministic 3×3 image shrinking to 2×3.**

```ts
const cpu = await forceWasmResize(fixture, 3, 3, 2, 3);
const gpu = await forceWebGPUResize(fixture, 3, 3, 2, 3);
expect(gpu.backend).toBe("webgpu");
expect(gpu.pixels).toEqual(cpu.pixels);
```

Skip only when `navigator.gpu` is unavailable; do not skip on a supported Chromium CI browser.

- [ ] **Step 2: Run it and verify it fails because the GPU processor is not implemented.**

Run: `cd Examples/WasmDemo/web && npx playwright test tests/webgpu-parity.spec.ts --project=chromium`

Expected: FAIL with GPU processor unavailable/not implemented.

- [ ] **Step 3: Implement WGSL luma/Sobel and exact first-seam DP pipeline.**

Use one `rgba8uint`-equivalent storage representation (packed `u32` words) so input/output bytes are lossless. Allocate storage buffers for source image, luma `f32`, energy `f32`, current/next DP row `f32`, parents `i32`, final argmin `u32`, seam `u32`, and output image. Encode luma, Sobel, first row initialization, one row DP dispatch per `y = 1..<height`, single-workgroup final reduce, backtrack, and removal in a single command encoder.

```ts
const encoder = device.createCommandEncoder();
encodeLuma(encoder, buffers, width, height);
encodeSobel(encoder, buffers, width, height);
for (let y = 1; y < height; y++) encodeDPRow(encoder, buffers, width, y);
encodeBacktrackAndRemove(encoder, buffers, width, height);
encoder.copyBufferToBuffer(buffers.currentImage, 0, readback, 0, outputBytes);
device.queue.submit([encoder.finish()]);
await readback.mapAsync(GPUMapMode.READ);
```

Match `SeamCarvingMetal/Shaders/SeamCarving.metal` and `BackwardEnergy.swift` for edge clamping, luma conversion, Sobel magnitude, parent tie order, final argmin tie order, and vertical removal indexing.

- [ ] **Step 4: Run parity plus the CPU fallback test.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/selector.spec.ts && cd Examples/WasmDemo/web && npx playwright test tests/webgpu-parity.spec.ts --project=chromium`

Expected: PASS with exact pixels for GPU and CPU fixture results.

- [ ] **Step 5: Commit one-seam GPU capability.**

```bash
git add Packages/SeamCarvingWasm/src Packages/SeamCarvingWasm/tests/webgpu-parity.spec.ts
git commit -m "feat: add WebGPU seam energy pipeline"
```

## Task 6: Complete multi-seam GPU jobs and error-path coverage

**Files:**
- Modify: `Packages/SeamCarvingWasm/src/webgpu.ts`
- Modify: `Packages/SeamCarvingWasm/src/selector.ts`
- Modify: `Packages/SeamCarvingWasm/src/shaders.ts`
- Test: `Examples/WasmDemo/web/tests/webgpu-parity.spec.ts`
- Test: `Packages/SeamCarvingWasm/tests/selector.spec.ts`

**Interfaces:**
- Extends `WebGPUProcessor.resize` to shrink from `sourceWidth` to any smaller `targetWidth` while keeping all intermediate data GPU resident.
- A GPU exception/device loss returns no pixels and selector routes once to CPU.

- [ ] **Step 1: Add failing multi-seam and device-loss tests.**

```ts
expect((await forceWebGPUResize(fixture, 8, 4, 5, 4)).pixels)
  .toEqual((await forceWasmResize(fixture, 8, 4, 5, 4)).pixels);
mockDeviceLostBeforeSubmit();
await expect(selector.resize(req(8, 4, 5, 4))).resolves.toMatchObject({ backend: "wasm-cpu" });
```

- [ ] **Step 2: Run tests and verify multi-seam fails after the first removal.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/selector.spec.ts && cd Examples/WasmDemo/web && npx playwright test tests/webgpu-parity.spec.ts --project=chromium`

Expected: FAIL on 8→5 output length or pixel mismatch.

- [ ] **Step 3: Implement buffer ping-pong and final-only map.**

```ts
for (let currentWidth = request.sourceWidth; currentWidth > request.targetWidth; currentWidth--) {
  encodeOneVerticalSeam(encoder, current, next, currentWidth, request.sourceHeight);
  [current, next] = [next, current];
}
encoder.copyBufferToBuffer(current.image, 0, readback, 0, targetBytes);
```

Allocate for original input dimensions once; use `currentWidth` bounds in every shader. Do not call `mapAsync`, `getMappedRange`, `queue.onSubmittedWorkDone`, or `postMessage` inside the loop. Clear cached GPU processor on `device.lost` and make the next eligible request retry initialization once.

- [ ] **Step 4: Run parity on 3→2, 8→5, and a 64×32 fixture; run fallback coverage.**

Run: `npm run test:unit --prefix Packages/SeamCarvingWasm -- tests/selector.spec.ts && cd Examples/WasmDemo/web && npx playwright test tests/webgpu-parity.spec.ts --project=chromium`

Expected: PASS; all GPU output byte arrays equal CPU output and lost-device test returns CPU result.

- [ ] **Step 5: Commit multi-seam and resilience behavior.**

```bash
git add Packages/SeamCarvingWasm/src Packages/SeamCarvingWasm/tests
git commit -m "feat: complete WebGPU vertical shrink"
```

## Task 7: Verify a packed external consumer and document the SDK

**Files:**
- Create: `Packages/SeamCarvingWasm/tests/fixtures/vite-consumer/package.json`
- Create: `Packages/SeamCarvingWasm/tests/fixtures/vite-consumer/index.html`
- Create: `Packages/SeamCarvingWasm/tests/fixtures/vite-consumer/src/main.ts`
- Create: `Packages/SeamCarvingWasm/tests/packed-consumer.spec.mjs`
- Modify: `Packages/SeamCarvingWasm/README.md`
- Modify: `Examples/WasmDemo/README.md`

**Interfaces:**
- Consumes only an `.tgz` created by `npm pack`; fixture cannot import package source by relative path.
- Produces a built Vite consumer that loads `@seemcarving/wasm`, creates a carver, and completes a 2×1 → 1×1 CPU fallback resize.

- [ ] **Step 1: Write a failing packed-consumer test.**

```js
execFileSync("npm", ["install", packedTarball], { cwd: consumerDir, stdio: "inherit" });
execFileSync("npm", ["run", "build"], { cwd: consumerDir, stdio: "inherit" });
assert.ok(existsSync(join(consumerDir, "dist", "assets")));
```

- [ ] **Step 2: Run it and verify it fails until package exports/assets resolve correctly.**

Run: `node --test Packages/SeamCarvingWasm/tests/packed-consumer.spec.mjs`

Expected: FAIL on missing Worker or WASM asset before asset URL handling is finalized.

- [ ] **Step 3: Fix Vite/export-map asset resolution and add public usage docs.**

Document the exact install/API path:

```ts
import { createSeamCarver } from "@seemcarving/wasm";
const carver = await createSeamCarver();
const result = await carver.resize({ pixels, width, height, targetWidth, targetHeight });
carver.terminate();
```

Document WebGPU-first eligibility, `wasm-cpu` fallback, Worker requirement, RGBA8 layout, limits, cancellation semantics, ESM/browser support, and no WebGL2 implementation. Update the demo README to name the package and distinguish it from the app.

- [ ] **Step 4: Run package build, packed consumer, demo build, and all Chromium tests.**

Run: `npm run build --prefix Packages/SeamCarvingWasm && node --test Packages/SeamCarvingWasm/tests/packed-consumer.spec.mjs && cd Examples/WasmDemo/web && npm run build && npx playwright test --project=chromium`

Expected: PASS.

- [ ] **Step 5: Commit public packaging and documentation.**

```bash
git add Packages/SeamCarvingWasm Examples/WasmDemo/README.md Examples/WasmDemo/web
git commit -m "docs: document published WASM SDK"
```

## Task 8: Add measurements and GitHub Actions gates

**Files:**
- Create: `Packages/SeamCarvingWasm/bench/benchmark.ts`
- Create: `.github/workflows/publish-npm.yml`
- Modify: `.github/workflows/wasm-demo.yml`
- Modify: `Packages/SeamCarvingWasm/package.json`
- Modify: `Packages/SeamCarvingWasm/README.md`
- Test: `.github/workflows/wasm-demo.yml` through `actionlint`
- Test: `.github/workflows/publish-npm.yml` through `actionlint`

**Interfaces:**
- Produces `npm run benchmark` JSON output with `backend`, input dimensions, target dimensions, warmup count, iterations, p50/p95 milliseconds.
- Produces tag-only publish workflow consuming no `NPM_TOKEN` and calling `npm publish --access public` from `Packages/SeamCarvingWasm`.

- [ ] **Step 1: Write failing tests/lints for workflow trigger and required OIDC permissions.**

```sh
grep -Fq "wasm-v*" .github/workflows/publish-npm.yml
grep -Fq "id-token: write" .github/workflows/publish-npm.yml
! grep -Fq "NPM_TOKEN" .github/workflows/publish-npm.yml
```

- [ ] **Step 2: Run them and verify they fail because no publish workflow exists.**

Run: `test -f .github/workflows/publish-npm.yml && actionlint .github/workflows/publish-npm.yml`

Expected: FAIL with file not found.

- [ ] **Step 3: Extend CI and add secure publishing workflow.**

The CI workflow must: install the pinned Swift SDK; run the boundary check; build/stage WASM; run `npm ci` in the standalone package and demo; package build; `node --test .../packed-consumer.spec.mjs`; demo static build; and Playwright browser matrix. Cache both lockfiles.

The release workflow must use `on.push.tags: ["wasm-v*"]`, `permissions: { contents: read, id-token: write }`, Node 24/npm ≥11.5.1, pinned Swift WASM build, package tests, clean pack test, a script that compares `process.env.GITHUB_REF_NAME.slice("wasm-v".length)` to `package.json.version`, and then:

```yaml
- name: Publish public package through npm OIDC
  working-directory: Packages/SeamCarvingWasm
  run: npm publish --access public
```

Upload the generated `.tgz` and a JSON manifest with SHA-256/version/tag as workflow artifacts. Configure `environment: npm` only if repository release approval is desired; do not assume npm trusted-publisher configuration can be created from GitHub.

- [ ] **Step 4: Implement the benchmark script and document its non-claiming interpretation.**

```ts
for (const backend of ["webgpu", "wasm-cpu"] as const) {
  await warmup(backend, fixture);
  report.samplesMs = await measure(iterations, () => resize(backend, fixture));
}
```

Write one JSON record per fixed generated input/target; report end-to-end time and selected backend. Do not state a performance improvement until physical browser results show it.

- [ ] **Step 5: Run workflow lint, package checks, and Chromium release-equivalent verification.**

Run: `actionlint .github/workflows/wasm-demo.yml .github/workflows/publish-npm.yml && Examples/WasmDemo/scripts/build-swift.sh && npm ci --prefix Packages/SeamCarvingWasm && npm run build --prefix Packages/SeamCarvingWasm && node --test Packages/SeamCarvingWasm/tests/packed-consumer.spec.mjs && cd Examples/WasmDemo/web && npm ci && npm run build && npx playwright test --project=chromium`

Expected: PASS.

- [ ] **Step 6: Commit CI, release, and benchmark work.**

```bash
git add .github/workflows Packages/SeamCarvingWasm
git commit -m "ci: publish WASM SDK with OIDC"
```

## Task 9: Full verification and independent review gate

**Files:**
- Modify only if verification identifies a defect.

**Interfaces:**
- Verifies the complete public `@seemcarving/wasm` implementation against the design acceptance criteria.

- [ ] **Step 1: Run source/boundary and all package tests.**

Run: `bash Scripts/check-target-boundaries.sh && bash Examples/WasmDemo/scripts/check-wasm-boundaries.sh && swift test --package-path Examples/WasmDemo/swift && npm run test:unit --prefix Packages/SeamCarvingWasm`

Expected: PASS.

- [ ] **Step 2: Run production package, pack-consumer, and browser matrix checks.**

Run: `Examples/WasmDemo/scripts/build-swift.sh && npm run build --prefix Packages/SeamCarvingWasm && node --test Packages/SeamCarvingWasm/tests/package-contents.spec.mjs Packages/SeamCarvingWasm/tests/packed-consumer.spec.mjs && cd Examples/WasmDemo/web && npm ci && npm run build && npx playwright test`

Expected: PASS on Chromium, Firefox, and WebKit; browsers without WebGPU use `wasm-cpu` fallback.

- [ ] **Step 3: Execute a warm benchmark and record factual results in the PR/commit notes.**

Run: `npm run benchmark --prefix Packages/SeamCarvingWasm -- --sizes 1280x720 --targets 1272x720 --warmup 3 --iterations 10`

Expected: JSON records for `webgpu` when available and `wasm-cpu`; do not fabricate unavailable-device results.

- [ ] **Step 4: Request a separate reviewer to inspect API stability, GPU/CPU parity, tarball contents, and OIDC workflow.**

Reviewer checklist:

```text
- No root package.json and no WebGPU imports in Swift sources.
- Package tarball runs without repository source paths.
- GPU supports only documented MVP requests and falls back otherwise.
- GPU output matches CPU fixtures exactly.
- Publish workflow is tag-only, has id-token: write, and has no long-lived npm token.
```

- [ ] **Step 5: Commit only review-driven fixes, then re-run the affected checks.**

```bash
git add <reviewed-files>
git commit -m "fix: address WASM SDK review"
```
