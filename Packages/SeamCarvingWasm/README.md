# @seemcarving/wasm

Browser ESM SDK for [SeamCarvingSwift](https://github.com/AmatsuZero/SeemCarvingSwift).
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

### Bundler-managed Worker

`@seemcarving/wasm/worker` is the package's Worker module entry. For bundlers
that need the application to construct the Worker, pass a factory that creates
a fresh module Worker for each carver:

```ts
import { createSeamCarver } from "@seemcarving/wasm";

const carver = await createSeamCarver({
  workerFactory: () => new Worker(
    new URL("@seemcarving/wasm/worker", import.meta.url),
    { type: "module" },
  ),
});
```

The package also exports `createWorker()` for its default Worker URL, so a
factory can delegate to it when the bundler supports package-relative Worker
assets: `createSeamCarver({ workerFactory: createWorker })`. The `worker`
option remains available for direct Worker injection in tests and embedding.

## Backend selection

The Worker is WebGPU-first only for a positive-width vertical shrink (the
target height is unchanged and the target width is smaller). When WebGPU is
unavailable, initialization fails, a GPU job/device is lost, or the request is
outside that MVP path, the same request runs through the Swift/WASM CPU backend
and returns `backend: "wasm-cpu"`. The CPU backend supports the bridge's full
resize operation. There is **no WebGL2 implementation**.

## Benchmarking

After staging the real Swift/WASM runtime and building the package, run a
physical Chromium benchmark (install Chromium first with `npx playwright install
chromium`):

```sh
npm run benchmark --prefix Packages/SeamCarvingWasm -- \
  --sizes 1280x720 --targets 1272x720 --warmup 3 --iterations 10
```

The command writes one JSON record per generated input/target/backend. Each
record includes the selected backend, input and target dimensions, warmup and
iteration counts, raw end-to-end resize samples, and nearest-rank p50/p95
milliseconds. It uses a normal Chromium launch for the WebGPU record and a
separate `--disable-gpu --disable-software-rasterizer` launch for the WASM CPU
record; it fails rather than mislabeling a CPU fallback as WebGPU when WebGPU
is unavailable. A missing WebGPU capability is reported after the CPU record,
so it does not discard the CPU measurement.

These are end-to-end SDK request timings after Worker initialization (including
the input copy, Worker messaging, processing, and output transfer), not a claim
that either backend is faster. Do not make a performance-improvement claim until
the same fixed matrix has completed in physical browsers with the recorded JSON
evidence.

## Publishing prerequisites

The repository/package owner must configure npm Trusted Publishing for
`@seemcarving/wasm` and this repository's `wasm-v*` tag workflow before the
first release. That npm-side association is an external owner action; this
repository deliberately does not attempt to create it and does not use an npm
automation token. Once it exists, the tag-only workflow validates the tag and
package version before publishing with GitHub OIDC.

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
- During asynchronous initialization, pass an `AbortSignal` as `signal` to
  terminate the Worker and reject the pending `createSeamCarver()` call. This
  lets UIs cancel a stale initialization before a carver is exposed.

## License

UNLICENSED. This package does not grant reuse rights until the repository
publishes a license.
