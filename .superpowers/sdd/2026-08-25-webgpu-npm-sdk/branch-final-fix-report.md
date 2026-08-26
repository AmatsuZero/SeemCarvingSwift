# Branch final-fix report

## P1: cancellation during SDK initialization

- `createSeamCarver()` now accepts `signal: AbortSignal`. Aborting during the
  Worker handshake terminates the Worker and rejects the pending creation.
- The demo creates each client with an `AbortController`; replacement aborts
  the stale initialization before creating its replacement. The stale promise
  is observed so cancellation cannot become an unhandled rejection.
- The demo's focused Playwright coverage exercises cancelling a newly-created,
  not-yet-ready client, asserts that the stale creation rejects as terminated,
  and waits for the replacement client to become ready.
- SDK unit coverage also covers abort-before-ready and the ready/abort race, so
  a terminated carver is never exposed from a stale creation.

## P2: public Worker API

- Exported `createWorker()` creates the default module Worker.
- `createSeamCarver()` supports `workerFactory` for bundler-owned Worker URL
  resolution, while retaining the direct `worker` test/embedding injection.
- The demo uses the documented `@seemcarving/wasm/worker` package entry through
  `workerFactory`.
- The package README documents the worker entry, factory override,
  `createWorker()`, and initialization cancellation.

## Verification

Passed:

- `npm run test:unit` in `Packages/SeamCarvingWasm` — 21 Vitest assertions and
  4 Node publication-version tests.
- `npx vitest run tests/client.spec.ts` — 8 focused client tests.
- `npx tsc --noEmit` in `Packages/SeamCarvingWasm`.
- A Vite compile of the package and demo with temporary generated-runtime stubs
  confirmed the package-worker factory URL is bundled by Vite. The temporary
  stubs and build output were removed afterward.

Not runnable in this checkout:

- `Examples/WasmDemo/scripts/build-swift.sh` fails before staging runtime assets:
  the installed `swift-6.3.3-RELEASE_wasm` SDK reports no target compatible with
  `wasm32-unknown-wasip1`. Consequently the real package build and Playwright
  demo suite cannot start because their required generated PackageToJS artifact
  is unavailable.
