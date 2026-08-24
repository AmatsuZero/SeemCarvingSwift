# WASM Browser Demo Design

## Goal

Deliver an experimental, fully local browser demo for content-aware image
resizing. A user can upload a PNG or JPEG, select target dimensions, run the
existing CPU seam-carving algorithm, preview the result, and download a PNG.

The published demo is static: `index.html`, JavaScript/CSS assets, and a
generated WebAssembly module. It has no server-side image upload, storage, or
processing.

## Scope and non-goals

The first release supports current Chrome, Safari, Firefox, and Edge with a
single-threaded CPU path. It accepts PNG/JPEG through browser APIs, preserves
the browser-normalized display orientation, and exports PNG.

It does not add Metal, Accelerate, Vision, Apple image bridges, GPU/WebGPU,
SIMD or threaded WASM, masks/object-removal UI, batch processing, or a
production-service SLA. It does not change a public API in
`SeamCarvingCore`.

## Architecture and dependency boundaries

Keep the root Swift package independent of all browser SDKs:

```text
root Package.swift
└── SeamCarvingCore

Examples/WasmDemo/swift (independent Swift package)
├── WasmBridge executable/entry target
│   └── local package dependency: SeamCarvingCore at ../../..
└── JavaScript interoperability/runtime tooling

Examples/WasmDemo/web (independent Node/Vite project)
├── browser UI, canvas, image decode, worker, and PNG download
└── loads the generated WasmBridge artifact
```

`Examples/WasmDemo/swift/Package.swift` is the only manifest that resolves a
pinned JavaScriptKit release and its `PackageToJS` command plugin. Its lock
file stays in that directory. The root `Package.swift` must not mention that
dependency, Node, Vite, or browser APIs. The demo uses JavaScriptKit's
established `JSObject`/`JSClosure` API, not the experimental BridgeJS export
macros.

The bridge imports only `SeamCarvingCore` and the approved JS interoperability
module. It must not import Accelerate, Metal, AppleRuntime, AppleImaging,
Vision, UIKit, AppKit, CoreVideo, CLI targets, or Benchmark. Core continues to
allow only Foundation and Dispatch imports and no conditional compilation.

## Pixel and interoperation contract

The Node/Vite worker sends a compact RGBA8 buffer and metadata to the Swift
bridge. The stable request/response shape is:

```swift
struct ResizeRGBA8Request {
    let pixels: [UInt8]
    let sourceWidth: Int
    let sourceHeight: Int
    let targetWidth: Int
    let targetHeight: Int
}

struct ResizeRGBA8Response {
    let pixels: [UInt8]
    let width: Int
    let height: Int
}
```

Both buffers are sRGB, straight-alpha, RGBA order, row-major, tightly packed,
and origin-zero at the top left. There is no row stride. Browser code obtains
the input with `CanvasRenderingContext2D.getImageData`; it writes a successful
response with `putImageData`.

The type definitions describe the internal, host-testable bridge boundary;
they are not a JavaScript ABI. The WASM entry uses JavaScriptKit in the module
worker to install one process-lifetime, strongly retained `onmessage` closure.
The closure reads `MessageEvent.data`, validates its `jobId`, numeric metadata,
and `ArrayBuffer`, then starts a retained Swift `Task` because
`SeamCarver.resize` is async. The task copies the buffer into
`ResizeRGBA8Request.pixels`, calls the bridge, copies the response bytes into a
new JS `ArrayBuffer`, and calls `postMessage` with that buffer as a
transferable. The main-thread/worker hop has no clone; JavaScript/WASM
conversion intentionally has one documented copy in each direction. A response
carries the originating `jobId`; the main thread ignores stale success or
failure messages after it has terminated and replaced a worker.

Both the main thread and worker reject numeric metadata that is not a positive
safe integer. The bridge rejects zero/negative dimensions, overflow in width × height × 4,
and a byte count that differs from that exact product. It creates
`RGBA8Image`, calls the existing `SeamCarver` CPU path, and produces the same
validated compact format. It does not decode or encode image files.

## Browser experience and data flow

1. The main thread decodes a selected PNG/JPEG with
   `createImageBitmap(file, { imageOrientation: "from-image" })`, then renders
   it to an sRGB input canvas.
2. It reads normalized RGBA8 pixels, displays source dimensions, and validates
   the requested target dimensions before work begins.
3. A module worker loads the `PackageToJS`-generated JavaScriptKit runtime,
   the generated WASM module, and its browser-side WASI Preview 1 shim before
   it starts the Swift entry point. The entry installs its message closure;
   the worker receives the `ArrayBuffer` as a transferable, calls the bridge,
   and transfers the response buffer back.
4. The main thread renders the output buffer to a second canvas and enables
   download. PNG export remains browser-native: `canvas.toBlob("image/png")`,
   object URL, then a temporary download anchor.

The page has file selection, numeric width/height inputs, resize, cancel, and
download controls. During computation it disables duplicate submission. First
release cancellation means terminating the active worker, discarding its
result, and starting a new initialized worker; it does not promise a
cooperative in-algorithm cancel message. It does not expose live progress until
an interop proof shows that callbacks work safely during the synchronous WASM
resize.

The first release rejects a source or target larger than 2,000,000 pixels and
rejects a request whose estimated seam work exceeds 80,000,000 pixel-visits.
The estimate is `(abs(sourceWidth - targetWidth) * sourceHeight) +
(abs(sourceHeight - targetHeight) * targetWidth)`. These explicit source,
target, and work limits bound both image allocation and long-running CPU work;
they may be raised only with recorded browser benchmarks and revised E2E
fixtures.

## Error, privacy, and performance policy

An undecodable file, invalid target, or image exceeding the pixel limit is
reported before calling Swift. Core validation errors, cancellation, and WASM
runtime errors are mapped to actionable UI messages while their diagnostic
detail remains in the browser console.

All source and result bytes stay in browser memory. The demo sends no image or
metadata to a server and clears page-held image state on refresh or replacement.

Compute runs in a Worker to keep canvas interaction responsive. Input and
output buffers are transferred rather than cloned across the main-thread/
worker boundary, while the documented JS/WASM copies remain. Initial support
is deliberately single-threaded CPU-only;
SIMD, shared-memory threads, GPU acceleration, and WebGPU require a separate
design and compatibility review.

## Toolchain and build

Use a pinned Swift toolchain and a precisely matching Swift WebAssembly SDK
installed with `swift sdk install`. Build the Swift portion with
`swift build --swift-sdk <pinned-wasm-sdk-id>`. Phase 1 pins a JavaScriptKit
tag/revision whose documented minimum Swift version is satisfied by that
toolchain, records the exact `swift package --disable-sandbox --swift-sdk
<pinned-wasm-sdk-id> js` command, and proves its output in a Vite module worker
under Chromium, Firefox, and WebKit. The selected SDK ID must be recorded in
the demo README and CI configuration, not assumed from an unversioned local
default. Swift's official SDK documentation is the source of truth for
installation and SDK selection.

The official Swift SDK currently produces WASI modules, not browser-native
modules. `PackageToJS` is therefore the required artifact producer: it emits
the JavaScriptKit runtime/loader plus the WASM file, and its generated runtime
owns the required `javascript_kit` imports and browser-side WASI shim. Vite
must copy these generated assets together, preserve their relative URLs in the
worker, and serve `.wasm` as `application/wasm`. A static-host smoke test must
verify that exact output rather than relying on Vite development behavior.

Use an LTS Node version, a committed npm lock file, and Vite solely in
`Examples/WasmDemo/web`. Vite packages `index.html`, TypeScript worker/UI
assets, and the generated Wasm artifact into a deployable static `dist/`
directory. Browser UI implementation is TypeScript, not Swift DOM code.

Do not make the demo's critical path depend on JavaScriptKit BridgeJS code
generation while it is experimental; upgrade the pinned JavaScriptKit release
or change the interop layer only in a separately reviewed dependency update.

## Tests and acceptance criteria

1. Keep all existing Core tests unchanged on macOS, Linux, and Windows.
2. Split the bridge into `WasmBridgeCore` (no interop dependency) and the
   JavaScriptKit-only entry. Add host-run `WasmBridgeCore` tests for valid
   buffer conversion, malformed byte count,
   nonpositive dimensions, overflow protection, no-op dimensions, shrink,
   enlargement, alpha preservation, and cancellation.
3. Add a WASM compile gate that builds both `SeamCarvingCore` and the bridge
   using the pinned SDK.
4. Add Playwright browser E2E tests in Chromium, Firefox, and WebKit. They use
   fixed PNG and JPEG fixtures, upload each fixture, resize it, assert output
   canvas dimensions and selected
   known RGBA pixels, download it, and verify a PNG was produced. They also
   cover invalid dimensions, the pixel limit, and cancellation. A release
   checklist separately records manual Safari and Edge verification.
5. Extend `Scripts/check-target-boundaries.sh` with a bridge rule: bridge
   source imports only Core and the approved interop module; Core's current
   import/conditional restrictions remain intact.

A supported experimental demo requires every item above to pass in CI, and a
manual check in each supported browser. Until then, documentation must call it
an experiment rather than platform support.

## CI and documentation

Add a separate `wasm-demo` workflow job. It installs the pinned Swift
toolchain and matching WASM SDK, Node LTS, and browser-test dependencies; it
caches Swift and npm artifacts; it builds the bridge, runs Node/Vite production
build, and runs Playwright tests. Existing Apple and Core-portability jobs do
not install Node or a WASM SDK and retain their current pass criteria.

Document local prerequisites, the exact build/test/deploy commands, static
hosting instructions, browser support, CPU-only behavior, source/target/work
limits,
privacy guarantee, and known limitations in `Examples/WasmDemo/README.md`.
Update the root README and capability matrix only after the CI gate is passing;
describe the result as an experimental browser demo, not general WASM platform
support.

## Delivery phases

1. **Feasibility gate:** install the selected SDK and compile the existing
   Core target. If Foundation, DispatchTime, or current concurrency use fails,
   make the smallest Core portability change that preserves its public API,
   then rerun host regressions.
2. **Bridge:** create the isolated Swift package; pin a compatible JavaScriptKit
   revision; prove the exact `swift package ... js` artifact in a Vite module
   worker; then implement the RGBA8 contract and pass bridge tests and a WASM
   compile smoke test.
3. **Demo:** create the Node/Vite single page and worker, complete upload,
   preview, resize, cancellation, and PNG download.
4. **Release gate:** add fixtures, Playwright E2E, CI, boundary enforcement,
   and documentation before advertising the demo.
