# WASM Browser Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an experimental, static browser demo that resizes local PNG/JPEG images through `SeamCarvingCore` compiled to WebAssembly.

**Architecture:** Keep the root package free of Web dependencies. An isolated Swift package builds `WasmBridgeCore` plus a JavaScriptKit worker entry, while a colocated Node/Vite app owns image decoding, canvas UI, Worker lifecycle, and PNG download. The generated WASI/JavaScriptKit assets are copied into a static Vite distribution.

**Tech Stack:** Swift 6.3.3 + matching official WASM SDK; JavaScriptKit 0.56.1 and PackageToJS; Node 24.11.1; TypeScript; Vite; Playwright; existing `SeamCarvingCore` and XCTest.

**Spec:** `docs/superpowers/specs/2026-08-24-wasm-browser-demo-design.md`

## Global Constraints

- Root `Package.swift` must not gain Node, Vite, JavaScriptKit, browser, or WASM dependencies.
- `WasmBridgeCore` depends only on `SeamCarvingCore`; its host tests do not link JavaScriptKit.
- The JavaScriptKit entry imports only `WasmBridgeCore`, `JavaScriptKit`, and `JavaScriptEventLoop`; never import Apple, CLI, benchmark, Accelerate, Metal, Vision, UIKit, AppKit, or CoreVideo modules.
- Pixel buffers are tightly packed sRGB, straight-alpha, top-left-origin RGBA8; browser decoding and PNG export stay in TypeScript/Canvas.
- Initial limits are source pixels ≤ 2,000,000, target pixels ≤ 2,000,000, and estimated seam work ≤ 80,000,000 pixel-visits.
- First release is single-threaded CPU-only; cancellation terminates/recreates the Worker and progress is not displayed.
- BridgeJS must not be used; pin JavaScriptKit 0.56.1 and use its `JSObject`/`JSClosure` API with PackageToJS.
- The published output is static and must never upload or persist user images.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `Examples/WasmDemo/swift/Package.swift` | Isolated Swift package and local dependency on the repository root. |
| `Examples/WasmDemo/swift/Sources/WasmBridgeCore/WasmBridgeCore.swift` | Validation, limits, RGBA8-to-Core conversion, and CPU resize. |
| `Examples/WasmDemo/swift/Sources/WasmBridgeWorker/main.swift` | Long-lived JavaScriptKit Worker listener and job-ID response protocol. |
| `Examples/WasmDemo/swift/Tests/WasmBridgeCoreTests/WasmBridgeCoreTests.swift` | Host XCTest coverage for bridge contracts. |
| `Examples/WasmDemo/swift/Package.resolved` | Locked JavaScriptKit dependency graph. |
| `Examples/WasmDemo/web/package.json` / `package-lock.json` | Pinned Node toolchain scripts and packages. |
| `Examples/WasmDemo/web/.nvmrc` / `playwright.config.ts` | Exact Node runtime and static-host E2E server/browser configuration. |
| `Examples/WasmDemo/web/index.html` | Accessible single-page UI shell. |
| `Examples/WasmDemo/web/src/main.ts` | File decode, dimensions, UI state, Canvas rendering, and download. |
| `Examples/WasmDemo/web/src/resize.worker.ts` | Worker creation/recreation, generated runtime initialization, and WASM messages. |
| `Examples/WasmDemo/web/src/protocol.ts` | Main-thread/Worker request, response, and error discriminated unions. |
| `Examples/WasmDemo/web/src/styles.css` | Responsive, accessible demo styling. |
| `Examples/WasmDemo/web/tests/demo.spec.ts` | Playwright static-host browser E2E suite. |
| `Examples/WasmDemo/web/tests/fixtures/*.png` / `*.jpg` | Small deterministic opaque/alpha and orientation fixtures. |
| `Examples/WasmDemo/README.md` | Exact prerequisites, build, test, deploy, privacy and limitation guidance. |
| `Examples/WasmDemo/scripts/build-swift.sh` | SDK-ID-checked PackageToJS build and asset copy for Vite. |
| `Examples/WasmDemo/scripts/check-wasm-boundaries.sh` | Enforces bridge import boundary without changing root target rules. |
| `.github/workflows/wasm-demo.yml` | Isolated WASM build and browser-test CI job. |
| `.gitignore` | Ignores Vite `dist`, Node modules, generated PackageToJS artifacts, and Playwright reports. |
| `README.md`, `README.zh-CN.md`, `docs/capability-matrix.md` | Advertise experimental status only after CI exists. |

## Task 1: Prove and pin the browser-WASM toolchain

**Files:**
- Create: `Examples/WasmDemo/swift/Package.swift`
- Create: `Examples/WasmDemo/swift/Sources/WasmBridgeWorker/main.swift`
- Create: `Examples/WasmDemo/web/package.json`
- Create: `Examples/WasmDemo/web/.nvmrc`
- Create: `Examples/WasmDemo/web/playwright.config.ts`
- Create: `Examples/WasmDemo/web/index.html`
- Create: `Examples/WasmDemo/web/src/resize.worker.ts`
- Create: `Examples/WasmDemo/scripts/build-swift.sh`
- Create: `Examples/WasmDemo/README.md`

**Interfaces:**
- Consumes: `SeamCarvingCore` through local package path `../../..`.
- Produces: a reproducible `swift package --disable-sandbox --swift-sdk swift-6.3.3-RELEASE_wasm js --product WasmBridgeWorker` build whose generated loader, WASI shim, JavaScriptKit runtime, and `.wasm` start inside a Vite module Worker.

- [ ] **Step 1: Write the failing module-worker smoke test**

Create `Examples/WasmDemo/web/tests/toolchain.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("generated Swift WASM worker announces readiness", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd Examples/WasmDemo/web && npm ci && npm run build && npx playwright test tests/toolchain.spec.ts --project=chromium`

Expected: FAIL because the generated Swift artifact and worker readiness message do not exist.

- [ ] **Step 3: Add the isolated manifests and pinned tools**

Set the Swift package tools version to 6.3 and add the root package plus JavaScriptKit 0.56.1:

```swift
.package(path: "../../.."),
.package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.56.1")
```

Make `WasmBridgeWorker` depend on `SeamCarvingCore`, `JavaScriptKit`, `JavaScriptEventLoop`, and the `PackageToJS` command plugin. Set `.nvmrc` to `24.11.1`. In `web/package.json`, set `engines.node` to `24.11.1`, `packageManager` to the npm version installed with that Node release, add `vite`, `typescript`, `@playwright/test`, and scripts named `dev`, `build`, `preview`, and `test:e2e`; run `npm install --package-lock-only` to commit the exact lockfile. Create `playwright.config.ts` in this task with a `webServer` that runs `npm run preview -- --host 127.0.0.1 --port 4173` against `dist/`, and projects for Chromium, Firefox, and WebKit.

Implement a minimal `main.swift` that first calls `JavaScriptEventLoop.installGlobalExecutor()`, retains a `JSClosure`, posts `{ type: "ready" }` to `self`, and keeps the event loop alive. Run PackageToJS with `--product WasmBridgeWorker`, record the generated output tree and entry-loader initialization call in `README.md` under “Pinned artifact contract”, then make `resize.worker.ts` import that recorded entry-loader path and call that recorded initializer. Configure Vite to copy `generated/` unchanged. `index.html` must contain `<output data-testid="worker-status">loading</output>`.

- [ ] **Step 4: Install and verify the matching SDK**

Run:

```bash
swiftly install 6.3.3
swiftly use 6.3.3
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7
swift sdk list
```

Expected: output contains `swift-6.3.3-RELEASE_wasm`.

- [ ] **Step 5: Implement the deterministic Swift artifact script**

Create `build-swift.sh` with SDK ID `swift-6.3.3-RELEASE_wasm`; it must fail if `swift sdk list` does not contain that exact ID, delete/recreate only `swift/generated`, then run:

```bash
swift package --disable-sandbox --swift-sdk swift-6.3.3-RELEASE_wasm js --product WasmBridgeWorker
```

Copy the complete generated product directory from `.build/plugins/PackageToJS/outputs/WasmBridgeWorker/` into `web/src/generated/`, preserving relative paths. Fail if the directory, entry-loader file recorded in README, or `.wasm` file is absent. Add `web/src/generated/` to `.gitignore`; Vite owns the final copy into `dist/`.

- [ ] **Step 6: Run build and smoke test to verify it passes**

Run:

```bash
cd Examples/WasmDemo
scripts/build-swift.sh
cd web
npm run build
npx playwright install --with-deps chromium
npx playwright test tests/toolchain.spec.ts --project=chromium
```

Expected: PackageToJS artifact generation succeeds and the worker status becomes `ready`.

- [ ] **Step 7: Commit**

```bash
git add Examples/WasmDemo .gitignore
git commit -m "build: bootstrap wasm demo toolchain"
```

## Task 2: Implement the host-testable RGBA8 bridge

**Files:**
- Create: `Examples/WasmDemo/swift/Sources/WasmBridgeCore/WasmBridgeCore.swift`
- Create: `Examples/WasmDemo/swift/Tests/WasmBridgeCoreTests/WasmBridgeCoreTests.swift`
- Modify: `Examples/WasmDemo/swift/Package.swift`

**Interfaces:**
- Consumes: `RGBA8Image(width:height:pixels:)`, `PixelSize(width:height:)`, and `SeamCarver().resize(_:to:)` from `SeamCarvingCore`.
- Produces: `public struct ResizeRGBA8Request: Sendable, Equatable`, `public struct ResizeRGBA8Response: Sendable, Equatable`, `public enum WasmBridgeError: Error, Equatable`, and `public func resizeRGBA8(_:) async throws -> ResizeRGBA8Response`.

- [ ] **Step 1: Write failing bridge tests**

```swift
func testResizeRGBA8ShrinksAndPreservesOutputLayout() async throws {
    let request = ResizeRGBA8Request(
        pixels: [255, 0, 0, 255, 0, 255, 0, 128],
        sourceWidth: 2, sourceHeight: 1, targetWidth: 1, targetHeight: 1
    )
    let result = try await resizeRGBA8(request)
    XCTAssertEqual(result.width, 1)
    XCTAssertEqual(result.height, 1)
    XCTAssertEqual(result.pixels.count, 4)
}

func testResizeRGBA8RejectsWrongByteCount() async {
    let request = ResizeRGBA8Request(pixels: [0, 0, 0], sourceWidth: 1, sourceHeight: 1, targetWidth: 1, targetHeight: 1)
    await XCTAssertThrowsErrorAsync { try await resizeRGBA8(request) }
}

func testResizeRGBA8RejectsSourceAndTargetLimits() async {
    let sourceTooLarge = ResizeRGBA8Request(pixels: [], sourceWidth: 2_000_001, sourceHeight: 1, targetWidth: 1, targetHeight: 1)
    await XCTAssertThrowsErrorAsync { try await resizeRGBA8(sourceTooLarge) }
}
```

Define `XCTAssertThrowsErrorAsync` in the same test file as an async closure helper that fails when no error is thrown. Add separate tests for nonpositive dimensions, integer multiplication overflow, target limit, work limit, no-op round trip, enlargement dimensions, and alpha byte preservation. Do not add a bridge cancellation test: browser cancellation is explicitly Worker termination and never reaches an in-flight Core call.

- [ ] **Step 2: Run the bridge tests to verify they fail**

Run: `cd Examples/WasmDemo/swift && swift test --filter WasmBridgeCoreTests`

Expected: FAIL because the bridge target and API do not exist.

- [ ] **Step 3: Implement minimal bridge validation and CPU call**

```swift
public func resizeRGBA8(_ request: ResizeRGBA8Request) async throws -> ResizeRGBA8Response {
    try validate(request)
    let image = try RGBA8Image(width: request.sourceWidth, height: request.sourceHeight, pixels: request.pixels)
    let target = try PixelSize(width: request.targetWidth, height: request.targetHeight)
    let result = try await SeamCarver().resize(image, to: target)
    return .init(pixels: result.pixels, width: result.width, height: result.height)
}
```

Implement checked multiplication locally for public bridge limits; map invalid values to named `WasmBridgeError` cases rather than exposing UI strings. Use the specified work formula and enforce all three limits before constructing any large array.

- [ ] **Step 4: Run bridge tests to verify they pass**

Run: `cd Examples/WasmDemo/swift && swift test --filter WasmBridgeCoreTests`

Expected: PASS for every `WasmBridgeCoreTests` case.

- [ ] **Step 5: Build Core and bridge for WASM**

Run:

```bash
swift build --package-path . --swift-sdk swift-6.3.3-RELEASE_wasm --target WasmBridgeCore
swift build --package-path ../../.. --swift-sdk swift-6.3.3-RELEASE_wasm --target SeamCarvingCore
```

Expected: both targets compile without importing any Web or Apple framework into Core.

- [ ] **Step 6: Commit**

```bash
git add Examples/WasmDemo/swift
git commit -m "feat: add wasm rgba8 core bridge"
```

## Task 3: Wire the Worker protocol and cancellable lifecycle

**Files:**
- Create: `Examples/WasmDemo/web/src/protocol.ts`
- Modify: `Examples/WasmDemo/swift/Sources/WasmBridgeWorker/main.swift`
- Modify: `Examples/WasmDemo/web/src/resize.worker.ts`
- Create: `Examples/WasmDemo/web/tests/worker-protocol.spec.ts`

**Interfaces:**
- Consumes: `resizeRGBA8(_:) async throws -> ResizeRGBA8Response`.
- Produces: `ResizeRequestMessage`, `ResizeSuccessMessage`, `ResizeFailureMessage`, `WorkerReadyMessage`, each with `jobId: number`; `createResizeWorker(): Worker`.

- [ ] **Step 1: Write failing worker protocol tests**

```ts
test("worker returns the same job ID and resized dimensions", async ({ page }) => {
  await page.goto("/");
  const result = await page.evaluate(() => window.__testResizeRGBA8(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1));
  expect(result).toMatchObject({ type: "success", jobId: 1, width: 1, height: 1 });
});

test("terminating a job ignores its late response", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => window.__testTerminateActiveWorker());
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
});
```

- [ ] **Step 2: Run protocol tests to verify they fail**

Run: `cd Examples/WasmDemo/web && npx playwright test tests/worker-protocol.spec.ts --project=chromium`

Expected: FAIL because no protocol or test hooks exist.

- [ ] **Step 3: Implement explicit message validation and replacement**

Define the TypeScript unions with `type`, `jobId`, dimensions, `pixels: ArrayBuffer`, and `message`. In the Worker, validate `Number.isSafeInteger` and the exact byte length before passing to Swift. In Swift, retain the `JSClosure`, read `MessageEvent.data`, start a retained `Task`, call `resizeRGBA8`, and post success/failure with the original ID. In `main.ts`, cancel by calling `worker.terminate()`, creating a new worker, and rejecting the old promise with `DOMException("Resize cancelled", "AbortError")`; ignore every response whose job ID differs from the active job. Reject with `Error("WASM worker initialization failed")` on `onerror` or a 10-second readiness timeout. Assign the `window.__testResizeRGBA8` hooks only when `import.meta.env.MODE === "test"`.

- [ ] **Step 4: Run protocol tests to verify they pass**

Run: `cd Examples/WasmDemo/web && npm run build && npx playwright test tests/worker-protocol.spec.ts --project=chromium`

Expected: PASS; no stale worker response changes visible state.

- [ ] **Step 5: Commit**

```bash
git add Examples/WasmDemo
git commit -m "feat: connect wasm resize worker"
```

## Task 4: Build the accessible Node/Vite single-page demo

**Files:**
- Modify: `Examples/WasmDemo/web/index.html`
- Create: `Examples/WasmDemo/web/src/main.ts`
- Create: `Examples/WasmDemo/web/src/styles.css`
- Create: `Examples/WasmDemo/web/tests/demo.spec.ts`

**Interfaces:**
- Consumes: `createResizeWorker()` and the worker protocol from Task 3.
- Produces: file input `#source-file`, number inputs `#target-width`/`#target-height`, buttons `#resize`, `#cancel`, `#download`, canvases `#source-canvas`/`#result-canvas`, live status `[role=status]`.

- [ ] **Step 1: Write the failing browser interaction tests**

```ts
test("uploads a PNG, resizes it, and enables PNG download", async ({ page }) => {
  await page.goto("/");
  await page.locator("#source-file").setInputFiles("tests/fixtures/rgba-2x1.png");
  await page.locator("#target-width").fill("1");
  await page.locator("#target-height").fill("1");
  await page.getByRole("button", { name: "Resize" }).click();
  await expect(page.locator("#result-canvas")).toHaveAttribute("width", "1");
  await expect(page.getByRole("button", { name: "Download PNG" })).toBeEnabled();
});
```

Add tests for JPEG decode/orientation fixture, invalid target, source/target/work limits, cancellation, and downloaded PNG signature `89 50 4E 47 0D 0A 1A 0A`. Assert exact RGBA bytes only for the PNG fixture; assert JPEG dimensions/orientation and channel values within a documented tolerance of 4.

- [ ] **Step 2: Run demo tests to verify they fail**

Run: `cd Examples/WasmDemo/web && npx playwright test tests/demo.spec.ts --project=chromium`

Expected: FAIL because UI controls and Canvas data flow do not exist.

- [ ] **Step 3: Implement file, Canvas, and download flow**

Use `createImageBitmap(file, { imageOrientation: "from-image" })`, draw it to an sRGB source canvas, call `getImageData`, enforce all limits before sending its transferable `ArrayBuffer`, and render successful pixels with `new ImageData(new Uint8ClampedArray(buffer), width, height)` plus `putImageData`. Implement PNG export with `canvas.toBlob("image/png")`, an object URL, and a temporary `a.download = "seamcarved.png"`; revoke the URL after click. Give every visible error an actionable status message and never call `fetch` for image data.

- [ ] **Step 4: Implement keyboard and state accessibility**

Associate labels with all fields, keep resize disabled until a valid image and target exist, expose status through `role="status" aria-live="polite"`, move focus to the error/status after validation failure, and use the native disabled state for unavailable cancel/download controls.

- [ ] **Step 5: Run the production bundle and browser tests**

Run:

```bash
cd Examples/WasmDemo/web
npm run build
npx playwright test tests/demo.spec.ts --project=chromium
```

Expected: PASS and `dist/` contains `index.html`, Vite assets, generated runtime assets, and a `.wasm` served with `application/wasm`.

- [ ] **Step 6: Commit**

```bash
git add Examples/WasmDemo/web
git commit -m "feat: add wasm browser resize demo"
```

## Task 5: Enforce boundaries, document the demo, and add CI

**Files:**
- Create: `Examples/WasmDemo/scripts/check-wasm-boundaries.sh`
- Create: `.github/workflows/wasm-demo.yml`
- Modify: `Examples/WasmDemo/README.md`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/capability-matrix.md`

**Interfaces:**
- Consumes: Task 1 artifact script, Task 2 bridge boundaries, Task 4 `npm run build` and `npm run test:e2e`.
- Produces: an independently reproducible `wasm-demo` CI check and accurate experimental-support documentation.

- [ ] **Step 1: Write failing boundary and static-host tests**

Create boundary checks that fail on any import outside this exact allowlist:

```text
WasmBridgeCore: SeamCarvingCore
WasmBridgeWorker: WasmBridgeCore, JavaScriptKit
```

Add a Playwright `webServer` configuration that serves `dist/` with a static server and runs the existing smoke test against it; no test may use Vite's development server.

- [ ] **Step 2: Run checks to verify they fail**

Run:

```bash
bash Examples/WasmDemo/scripts/check-wasm-boundaries.sh
cd Examples/WasmDemo/web && npm run test:e2e
```

Expected: FAIL because boundary checker and static-host configuration do not exist.

- [ ] **Step 3: Implement the CI workflow**

Create a `wasm-demo` job that checks out the repository; installs Swift 6.3.3, the exact SDK bundle/checksum from Task 1, Node 24, and Playwright Chromium/Firefox/WebKit; restores Swift/npm caches keyed by `Package.resolved` and `package-lock.json`; runs boundary check, `scripts/build-swift.sh`, `npm ci`, `npm run build`, and `npm run test:e2e`. Upload Playwright reports on failure. Do not add Node or WASM setup to `core-portability.yml`.

- [ ] **Step 4: Write operator documentation**

Document exact Swift/SDK/Node prerequisites, `scripts/build-swift.sh`, `npm ci`, `npm run dev`, `npm run build`, `npm run test:e2e`, and static-host deployment. State: experimental browser demo; CPU-only; no image upload; 2 MP source/target and 80M-work limits; single-worker termination cancellation; no live progress; supported browser matrix; manual Safari/Edge release checklist.

- [ ] **Step 5: Update root capability statements only after checks pass**

Replace the current “Wasm … not supported platform” wording with “experimental browser demo” and link its README. Keep the statement that full WASM platform, image I/O library, CLI, and application support are not implied.

- [ ] **Step 6: Run the final verification matrix**

Run:

```bash
bash Scripts/check-target-boundaries.sh
swift test --parallel
bash Examples/WasmDemo/scripts/check-wasm-boundaries.sh
cd Examples/WasmDemo
scripts/build-swift.sh
cd web
npm ci
npm run build
npm run test:e2e
```

Expected: Core regressions pass; boundary checks pass; the static distribution passes Chromium, Firefox, and WebKit E2E tests.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/wasm-demo.yml .gitignore Examples/WasmDemo README.md README.zh-CN.md docs/capability-matrix.md
git commit -m "ci: verify wasm browser demo"
```

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 establish isolated toolchain and Core bridge; Tasks 3–4 deliver the Worker/Canvas UI, privacy, cancellation, limits, and PNG export; Task 5 adds browser matrix CI, boundaries, docs, and capability wording.
- **Placeholder scan:** Every task names concrete paths, interfaces, commands, and expected outcomes. The only generated artifact names are deliberately discovered from the pinned PackageToJS output and copied wholesale so the plan does not hard-code a fragile upstream filename.
- **Type consistency:** Swift Core inputs/outputs are `ResizeRGBA8Request` and `ResizeRGBA8Response`; TypeScript transports matching `ArrayBuffer`, dimensions, and `jobId` fields; all user-visible compute routes through `resizeRGBA8(_:)`.
