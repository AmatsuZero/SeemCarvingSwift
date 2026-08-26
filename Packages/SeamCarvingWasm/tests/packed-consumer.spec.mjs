import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { cpSync, existsSync, lstatSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const packageDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixtureDir = join(packageDir, "tests", "fixtures", "vite-consumer");

function packPackage() {
  const packed = JSON.parse(
    execFileSync("npm", ["pack", "--json"], { cwd: packageDir, encoding: "utf8" }),
  );
  const { filename } = Array.isArray(packed) ? packed[0] : Object.values(packed)[0];
  return resolve(packageDir, filename);
}

async function availablePort() {
  const server = createServer();
  await new Promise((resolvePort, rejectPort) => {
    server.once("error", rejectPort);
    server.listen(0, "127.0.0.1", resolvePort);
  });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  await new Promise((resolveClose, rejectClose) => server.close((error) => error ? rejectClose(error) : resolveClose()));
  return address.port;
}

async function waitForPreview(url, preview) {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    if (preview.exitCode !== null) throw new Error(`Vite preview exited with ${preview.exitCode}`);
    try {
      const response = await fetch(url);
      if (response.ok) return;
    } catch {
      // Vite has not accepted connections yet.
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error(`Timed out waiting for Vite preview at ${url}`);
}

async function stopPreview(preview) {
  if (!preview || preview.exitCode !== null) return;
  const exited = new Promise((resolveExit) => preview.once("exit", resolveExit));
  preview.kill();
  await exited;
}

test("a Vite app runs a packed SDK CPU fallback without repository source imports", async () => {
  const consumerDir = mkdtempSync(join(tmpdir(), "seemcarving-vite-consumer-"));
  let packedTarball;
  let preview;
  let browser;

  try {
    cpSync(fixtureDir, consumerDir, { recursive: true });
    packedTarball = packPackage();

    execFileSync("npm", ["install", "--no-save", packedTarball], {
      cwd: consumerDir,
      stdio: "inherit",
    });
    execFileSync("npm", ["run", "build"], { cwd: consumerDir, stdio: "inherit" });

    const assetDir = join(consumerDir, "dist", "assets");
    assert.ok(existsSync(assetDir));
    assert.ok(existsSync(join(assetDir, "generated", "WasmBridgeWorker.wasm")));
    const installedPackage = join(consumerDir, "node_modules", "@seemcarving", "wasm");
    const installedRealPath = realpathSync(installedPackage);
    const consumerRealPath = realpathSync(consumerDir);
    const installedRelativePath = relative(consumerRealPath, installedRealPath);
    assert.equal(lstatSync(installedPackage).isSymbolicLink(), false, "npm must unpack the tarball, not link it");
    assert.ok(
      installedRelativePath && !installedRelativePath.startsWith("..") && !isAbsolute(installedRelativePath),
      "the installed SDK must remain inside the temporary consumer",
    );
    assert.notEqual(
      installedRealPath,
      realpathSync(packageDir),
      "the consumer must not resolve to the repository package",
    );

    const bundledScripts = readdirSync(assetDir, { recursive: true })
      .filter((entry) => entry.endsWith(".js"))
      .map((entry) => readFileSync(join(assetDir, entry), "utf8"));
    assert.ok(bundledScripts.length > 0, "Vite must emit JavaScript assets");
    assert.doesNotMatch(bundledScripts.join("\n"), /SeamCarvingWasm\/src/);

    const port = await availablePort();
    const previewURL = `http://127.0.0.1:${port}`;
    preview = spawn("npm", ["run", "preview", "--", "--host", "127.0.0.1", "--port", String(port)], {
      cwd: consumerDir,
      stdio: "inherit",
    });
    await waitForPreview(previewURL, preview);

    const requireFromConsumer = createRequire(join(consumerDir, "package.json"));
    const { chromium } = requireFromConsumer("playwright");
    browser = await chromium.launch({ args: ["--disable-gpu", "--disable-software-rasterizer"] });
    const page = await browser.newPage();
    await page.goto(previewURL);
    await page.locator("#result[data-status='complete'][data-backend='wasm-cpu']").waitFor();
    await expectCpuFallback(page);
  } finally {
    try {
      await browser?.close();
    } finally {
      try {
        await stopPreview(preview);
      } finally {
        if (packedTarball) rmSync(packedTarball, { force: true });
        rmSync(consumerDir, { force: true, recursive: true });
      }
    }
  }
});

async function expectCpuFallback(page) {
  assert.equal(await page.locator("#result").getAttribute("data-backend"), "wasm-cpu");
  assert.match(await page.locator("#result").textContent() ?? "", /^Resized with wasm-cpu$/);
}
