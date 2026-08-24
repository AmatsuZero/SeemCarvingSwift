# Experimental browser WASM demo

This static experiment runs the CPU-only `SeamCarvingCore` build locally in a
browser Worker. It is not production platform support. It does not upload,
persist, or otherwise send image bytes to a server.

## Prerequisites

- Swift 6.3.3 and the exact `swift-6.3.3-RELEASE_wasm` SDK.
- Node 24.11.1 (see `web/.nvmrc`) and its bundled npm.
- Chromium/Firefox/WebKit browser binaries installed by Playwright for E2E
  testing.

Install the SDK with the official artifact and checksum:

```sh
swift sdk install https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7
swift sdk list
```

## Build and smoke test

```sh
cd Examples/WasmDemo
scripts/build-swift.sh
cd web
npm ci
npm run build
npx playwright install --with-deps chromium
npx playwright test tests/toolchain.spec.ts --project=chromium
```

`web/dist/` is a static-hosting artifact. Serve it with a host that sends
`.wasm` as `application/wasm`; it has no server endpoints or image upload.

## Pinned artifact contract

The command below is the compatibility contract for JavaScriptKit 0.56.1:

```sh
cd Examples/WasmDemo/swift
swift package --disable-sandbox --swift-sdk swift-6.3.3-RELEASE_wasm js --product WasmBridgeWorker
```

Its actual generated tree is:

```text
.build/plugins/PackageToJS/outputs/Package/
├── WasmBridgeWorker.wasm
├── index.js
├── instantiate.js
├── runtime.js
└── platforms/
    ├── browser.js
    ├── browser.worker.js
    └── node.js
```

Although the executable product is named `WasmBridgeWorker`, PackageToJS 0.56.1
uses the default `outputs/Package/` directory unless invoked with `--output`.
`index.js` exports the entry loader `init`; the Vite module Worker uses the
recorded initializer:

```ts
import { init } from "./generated/index.js";
await init();
```

`build-swift.sh` verifies that tree and copies it unchanged to
`web/src/generated/` before Vite constructs the static distribution.

## Limitations

The initial release is single-threaded and CPU-only. Future image UI work must
keep RGBA8 pixels tightly packed, sRGB, straight-alpha, and top-left-origin;
use browser Canvas for decode and PNG export. The intended limits are source
and target images of at most 2,000,000 pixels and estimated seam work of at
most 80,000,000 pixel-visits.
