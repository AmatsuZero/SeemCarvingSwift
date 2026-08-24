# Experimental browser WASM demo

This is an **experimental**, static browser demo, not general WebAssembly
platform support. It runs the CPU-only `SeamCarvingCore` path locally in a
browser Worker. Source images and results stay in browser memory: the demo has
no server endpoints and never uploads or persists image bytes.

The demo does **not** add a portable image-I/O library, CLI, or application
support. Browser Canvas owns PNG/JPEG decode and PNG export; the isolated Swift
package only resizes compact RGBA8 pixels.

## Prerequisites

- Swift **6.3.3** and the exact `swift-6.3.3-RELEASE_wasm` SDK.
- Node **24.11.1** (see `web/.nvmrc`) and its bundled npm.
- Playwright browser binaries for each browser being tested.

Install the pinned SDK with the official artifact and checksum:

```sh
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7
swift sdk list
```

The second command must list `swift-6.3.3-RELEASE_wasm`.

## Build, run, and test

```sh
cd Examples/WasmDemo
scripts/build-swift.sh

cd web
npm ci
npm run dev
```

`npm run dev` is for local development only. To build and test the deployable
static artifact instead:

```sh
cd Examples/WasmDemo
scripts/build-swift.sh
cd web
npm ci
npm run build
npx playwright install chromium firefox webkit
npm run test:e2e
```

The Playwright configuration always starts `vite preview` from `dist/`; it does
not test through the Vite development server.

| Browser | Experimental verification |
| --- | --- |
| Chromium | Playwright CI |
| Firefox | Playwright CI |
| WebKit | Playwright CI |
| Safari | Manual release checklist |
| Microsoft Edge | Manual release checklist |

Before a release/demo presentation, deploy the exact production `dist/` and
manually use Safari and Microsoft Edge to upload a PNG/JPEG, resize it, cancel
a resize, and download the resulting PNG.

## Static deployment

After `npm run build`, deploy `web/dist/` unchanged to any static host. Configure
the host to serve `.wasm` with `Content-Type: application/wasm`. There is no
backend configuration, image upload endpoint, or persistent storage required.

## Limits and behavior

- Source and target images are limited to **2,000,000 pixels** each.
- Estimated seam work is limited to **80,000,000 pixel-visits**:
  `(abs(sourceWidth - targetWidth) * sourceHeight) +
  (abs(sourceHeight - targetHeight) * targetWidth)`.
- Processing is single-threaded and CPU-only inside a module Worker.
- Cancel terminates and recreates that Worker; it is not cooperative in-algorithm
  cancellation. No live progress is reported.
- Pixels are tightly packed, top-left-origin, sRGB, straight-alpha RGBA8. Canvas
  performs decode and PNG export.

## Pinned artifact contract

The command below is the compatibility contract for JavaScriptKit 0.56.1:

```sh
cd Examples/WasmDemo/swift
swift package --disable-sandbox --swift-sdk swift-6.3.3-RELEASE_wasm js --product WasmBridgeWorker
```

Its generated tree is copied unchanged by `scripts/build-swift.sh` from
`.build/plugins/PackageToJS/outputs/Package/` into `web/src/generated/`:

```text
Package/
├── WasmBridgeWorker.wasm
├── index.js
├── instantiate.js
├── runtime.js
└── platforms/
    ├── browser.js
    ├── browser.worker.js
    └── node.js
```

`index.js` exports `init`, which the Vite module Worker invokes with `await
init()`. The generated JavaScriptKit runtime and browser-side WASI shim must
remain together with the `.wasm` file.

## Boundary check

Before changing bridge code, run:

```sh
bash Examples/WasmDemo/scripts/check-wasm-boundaries.sh
```

It permits only `SeamCarvingCore` in `WasmBridgeCore`, and only
`WasmBridgeCore`, `JavaScriptKit`, and `JavaScriptEventLoop` in the executable
worker. The root Swift package intentionally has no Node, Vite, JavaScriptKit,
or browser dependency.
