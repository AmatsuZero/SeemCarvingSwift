import { createServer } from "node:http";
import { access, readFile } from "node:fs/promises";
import { extname, relative, resolve } from "node:path";
import { chromium } from "@playwright/test";

type Dimensions = { width: number; height: number };
type BenchmarkOptions = {
  inputs: Dimensions[];
  targets: Dimensions[];
  warmup: number;
  iterations: number;
};
type BrowserBenchmarkResult = { backend: "webgpu" | "wasm-cpu"; samplesMs: number[] };
type BenchmarkRecord = {
  backend: "webgpu" | "wasm-cpu";
  input: Dimensions;
  target: Dimensions;
  warmup: number;
  iterations: number;
  p50Ms: number;
  p95Ms: number;
  samplesMs: number[];
};

const packageRoot = resolve(import.meta.dirname, "..");
const distRoot = resolve(packageRoot, "dist");

function parseDimensions(value: string): Dimensions {
  const match = /^(\d+)x(\d+)$/.exec(value);
  if (!match) throw new Error(`Expected dimensions in WIDTHxHEIGHT form, received ${value}`);
  const width = Number(match[1]);
  const height = Number(match[2]);
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1) {
    throw new Error(`Dimensions must be positive safe integers, received ${value}`);
  }
  return { width, height };
}

function parsePositiveInteger(name: string, value: string | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) throw new Error(`${name} must be a positive integer`);
  return parsed;
}

function optionValue(arguments_: string[], name: string): string | undefined {
  const index = arguments_.indexOf(name);
  if (index === -1) return undefined;
  const value = arguments_[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
  return value;
}

function parseOptions(arguments_: string[]): BenchmarkOptions {
  const inputValues = (optionValue(arguments_, "--sizes") ?? "256x144").split(",");
  const targetValues = (optionValue(arguments_, "--targets") ?? "248x144").split(",");
  const inputs = inputValues.map(parseDimensions);
  const targets = targetValues.map(parseDimensions);
  if (inputs.length !== targets.length) {
    throw new Error("--sizes and --targets must contain the same number of comma-separated dimensions");
  }
  for (const [index, input] of inputs.entries()) {
    const target = targets[index];
    if (target.width > input.width || target.height > input.height) {
      throw new Error(`Target ${target.width}x${target.height} must not enlarge input ${input.width}x${input.height}`);
    }
  }
  return {
    inputs,
    targets,
    warmup: parsePositiveInteger("--warmup", optionValue(arguments_, "--warmup"), 3),
    iterations: parsePositiveInteger("--iterations", optionValue(arguments_, "--iterations"), 10),
  };
}

function nearestRank(samples: number[], percentile: number): number {
  const sorted = [...samples].sort((left, right) => left - right);
  return sorted[Math.ceil(percentile * sorted.length) - 1];
}

function contentType(pathname: string): string {
  switch (extname(pathname)) {
    case ".html": return "text/html; charset=utf-8";
    case ".js": return "text/javascript; charset=utf-8";
    case ".wasm": return "application/wasm";
    default: return "application/octet-stream";
  }
}

const page = `<!doctype html>
<meta charset="utf-8">
<title>SeamCarving WASM benchmark</title>
<script type="module">
  window.runSeamCarvingBenchmark = async ({ input, target, warmup, iterations, expectedBackend }) => {
    const { createSeamCarver } = await import("/index.js");
    const pixels = new Uint8Array(input.width * input.height * 4);
    for (let y = 0; y < input.height; y += 1) {
      for (let x = 0; x < input.width; x += 1) {
        const offset = (y * input.width + x) * 4;
        // Fixed deterministic gradient/noise-like fixture; no image decode is timed.
        pixels[offset] = (x * 17 + y * 13) & 255;
        pixels[offset + 1] = (x * 7 + y * 29) & 255;
        pixels[offset + 2] = (x * 31 + y * 5) & 255;
        pixels[offset + 3] = 255;
      }
    }

    const carver = await createSeamCarver();
    try {
      const resize = async () => {
        const start = performance.now();
        const result = await carver.resize({
          pixels: new Uint8Array(pixels),
          width: input.width,
          height: input.height,
          targetWidth: target.width,
          targetHeight: target.height,
        });
        const elapsedMs = performance.now() - start;
        if (result.backend !== expectedBackend) {
          throw new Error("Expected " + expectedBackend + " but selected " + result.backend);
        }
        return elapsedMs;
      };

      for (let index = 0; index < warmup; index += 1) await resize();
      const samplesMs = [];
      for (let index = 0; index < iterations; index += 1) samplesMs.push(await resize());
      return { backend: expectedBackend, samplesMs };
    } finally {
      carver.terminate();
    }
  };
</script>`;

async function startServer(): Promise<{ url: string; close: () => Promise<void> }> {
  const server = createServer(async (request, response) => {
    try {
      const pathname = new URL(request.url ?? "/", "http://localhost").pathname;
      if (pathname === "/" || pathname === "/benchmark.html") {
        response.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
        response.end(page);
        return;
      }

      const requested = resolve(distRoot, `.${pathname}`);
      if (relative(distRoot, requested).startsWith("..")) {
        response.writeHead(403).end();
        return;
      }
      const file = await readFile(requested);
      response.writeHead(200, { "content-type": contentType(requested), "cache-control": "no-store" });
      response.end(file);
    } catch {
      response.writeHead(404).end();
    }
  });
  await new Promise<void>((resolveListen, rejectListen) => {
    server.once("error", rejectListen);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Benchmark server did not receive a TCP port");
  return {
    url: `http://127.0.0.1:${address.port}/benchmark.html`,
    close: () => new Promise((resolveClose, rejectClose) => server.close((error) => error ? rejectClose(error) : resolveClose())),
  };
}

async function measureBackend(
  url: string,
  backend: "webgpu" | "wasm-cpu",
  input: Dimensions,
  target: Dimensions,
  warmup: number,
  iterations: number,
): Promise<BrowserBenchmarkResult> {
  const browser = await chromium.launch(backend === "wasm-cpu" ? { args: ["--disable-webgpu"] } : {});
  try {
    const browserPage = await browser.newPage();
    await browserPage.goto(url, { waitUntil: "networkidle" });
    await browserPage.waitForFunction(() => typeof (window as typeof window & { runSeamCarvingBenchmark?: unknown }).runSeamCarvingBenchmark === "function");
    return await browserPage.evaluate(async (parameters) => {
      const run = (window as typeof window & {
        runSeamCarvingBenchmark: (input: typeof parameters) => Promise<BrowserBenchmarkResult>;
      }).runSeamCarvingBenchmark;
      return run(parameters);
    }, { input, target, warmup, iterations, expectedBackend: backend });
  } finally {
    await browser.close();
  }
}

async function main(): Promise<void> {
  const options = parseOptions(process.argv.slice(2));
  try {
    await access(resolve(distRoot, "index.js"));
  } catch {
    throw new Error("Built SDK is missing dist/index.js; run npm run build after staging the real Swift/WASM runtime");
  }
  const server = await startServer();
  try {
    for (const [index, input] of options.inputs.entries()) {
      const target = options.targets[index];
      for (const backend of ["webgpu", "wasm-cpu"] as const) {
        const result = await measureBackend(server.url, backend, input, target, options.warmup, options.iterations);
        const record: BenchmarkRecord = {
          backend: result.backend,
          input,
          target,
          warmup: options.warmup,
          iterations: options.iterations,
          p50Ms: nearestRank(result.samplesMs, 0.5),
          p95Ms: nearestRank(result.samplesMs, 0.95),
          samplesMs: result.samplesMs,
        };
        process.stdout.write(`${JSON.stringify(record)}\n`);
      }
    }
  } finally {
    await server.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
