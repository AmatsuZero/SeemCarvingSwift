# @seemcarving/wasm

Browser ESM SDK for [SeamCarvingSwift](https://github.com/samzhangjy/SeamCarvingSwift).
It performs seam-carving on tightly packed RGBA8 image data in a module Worker.

## Install and use

```sh
npm install @seemcarving/wasm
```

```ts
import { createSeamCarver } from "@seemcarving/wasm";

const carver = await createSeamCarver();
try {
  const result = await carver.resize({ pixels, width, height, targetWidth, targetHeight });
  // result.pixels is a new Uint8Array; result.backend is "webgpu" or "wasm-cpu".
} finally {
  carver.terminate();
}
```

The SDK is browser-only ESM. It requires module Worker support and a bundler or
static host that serves the generated `.wasm` file as `application/wasm`; it
does not provide a CommonJS, Node.js, or SSR implementation. The package
creates its module Worker automatically. If an application bundler relocates
the Worker, copy `node_modules/@seemcarving/wasm/dist/generated/` to
`assets/generated/` in the build output: those generated PackageToJS modules and
the WASM binary use relative URLs from Vite's emitted Worker. The included Vite
consumer fixture and demo contain that runtime-copy plugin.

## Backend selection

The Worker is WebGPU-first only for a positive-width vertical shrink (the
target height is unchanged and the target width is smaller). When WebGPU is
unavailable, initialization fails, a GPU job/device is lost, or the request is
outside that MVP path, the same request runs through the Swift/WASM CPU backend
and returns `backend: "wasm-cpu"`. The CPU backend supports the bridge's full
resize operation. There is **no WebGL2 implementation**.

## Input, limits, and lifecycle

- `pixels` must contain exactly `width * height * 4` bytes: tightly packed,
  row-major, top-left-origin, sRGB, straight-alpha RGBA8 (`R, G, B, A`).
- All dimensions must be positive. Source and target images are each limited to
  **2,000,000 pixels**. Estimated seam work is limited to **80,000,000
  pixel-visits**: `(abs(width - targetWidth) * height) +
  (abs(height - targetHeight) * targetWidth)`.
- One resize may be active on a carver. The SDK transfers a copy of the input,
  so the caller retains its original buffer.
- `terminate()` terminates the Worker, rejects its active request, and makes
  that carver unusable. Cancellation is not cooperative inside the seam
  algorithm: create a new carver for a later resize. No progress events are
  exposed.

## License

UNLICENSED. This package does not grant reuse rights until the repository
publishes a license.
