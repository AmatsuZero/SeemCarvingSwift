import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { createIsolatedNpmEnvironment } from "../scripts/isolated-npm.mjs";

const packageDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fixtureDir = join(packageDir, "tests", "fixtures", "vite-consumer");

function packPackage(env) {
  const packed = JSON.parse(
    execFileSync("npm", ["pack", "--json"], { cwd: packageDir, encoding: "utf8", env }),
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

test("npm child commands ignore a polluted user configuration", () => {
  const pollutedConfigDir = mkdtempSync(join(tmpdir(), "seemcarving-polluted-npm-config-"));
  const pollutedUserConfig = join(pollutedConfigDir, "npmrc");
  writeFileSync(pollutedUserConfig, "allow-scripts=oh-my-codex\n");

  try {
    const isolatedNpm = createIsolatedNpmEnvironment({
      ...process.env,
      NPM_CONFIG_USERCONFIG: pollutedUserConfig,
      NPM_CONFIG_ALLOW_SCRIPTS: "oh-my-codex",
      npm_config_ignore_scripts: "false",
    });

    try {
      const effectiveUserConfig = execFileSync("npm", ["config", "get", "userconfig"], {
        encoding: "utf8",
        env: isolatedNpm.env,
      }).trim();
      const allowedScripts = execFileSync("npm", ["config", "get", "allow-scripts"], {
        encoding: "utf8",
        env: isolatedNpm.env,
      }).trim();
      const ignoresLifecycleScripts = execFileSync("npm", ["config", "get", "ignore-scripts"], {
        encoding: "utf8",
        env: isolatedNpm.env,
      }).trim();

      assert.equal(effectiveUserConfig, isolatedNpm.userConfig);
      assert.notEqual(allowedScripts, "oh-my-codex");
      assert.equal(ignoresLifecycleScripts, "false");
    } finally {
      isolatedNpm.cleanup();
    }
  } finally {
    rmSync(pollutedConfigDir, { force: true, recursive: true });
  }
});

test("isolated npm runs build hooks but blocks installed tarball lifecycle scripts", () => {
  const testDirectory = mkdtempSync(join(tmpdir(), "seemcarving-npm-lifecycle-"));
  const consumerDir = join(testDirectory, "consumer");
  const packageRoot = join(testDirectory, "package-root");
  const untrustedPackageDir = join(packageRoot, "package");
  const packedTarball = join(testDirectory, "untrusted-package.tgz");
  const buildMarker = join(testDirectory, "build-lifecycle.txt");
  const installMarker = join(testDirectory, "install-lifecycle.txt");
  const appendMarker = (phase) =>
    `node -e \"require('node:fs').appendFileSync(process.env.SEEMCARVING_BUILD_MARKER, '${phase}\\n')\"`;

  mkdirSync(consumerDir);
  mkdirSync(untrustedPackageDir, { recursive: true });
  writeFileSync(join(consumerDir, "package.json"), JSON.stringify({
    name: "isolated-npm-consumer",
    private: true,
    scripts: {
      prebuild: appendMarker("prebuild"),
      build: appendMarker("build"),
      postbuild: appendMarker("postbuild"),
    },
  }));
  writeFileSync(join(untrustedPackageDir, "package.json"), JSON.stringify({
    name: "untrusted-lifecycle-package",
    version: "1.0.0",
    scripts: {
      postinstall: "node -e \"require('node:fs').writeFileSync(process.env.SEEMCARVING_INSTALL_MARKER, 'ran')\"",
    },
  }));

  const isolatedNpm = createIsolatedNpmEnvironment();
  try {
    execFileSync("tar", ["-czf", packedTarball, "package"], { cwd: packageRoot });
    execFileSync("npm", ["run", "build"], {
      cwd: consumerDir,
      env: {
        ...isolatedNpm.env,
        SEEMCARVING_BUILD_MARKER: buildMarker,
        SEEMCARVING_INSTALL_MARKER: installMarker,
      },
    });
    assert.equal(readFileSync(buildMarker, "utf8"), "prebuild\nbuild\npostbuild\n");

    execFileSync("npm", ["install", "--ignore-scripts", "--no-save", packedTarball], {
      cwd: consumerDir,
      env: {
        ...isolatedNpm.env,
        SEEMCARVING_BUILD_MARKER: buildMarker,
        SEEMCARVING_INSTALL_MARKER: installMarker,
      },
    });
    assert.equal(existsSync(installMarker), false);
  } finally {
    isolatedNpm.cleanup();
    rmSync(testDirectory, { force: true, recursive: true });
  }
});

test("a Vite app runs a packed SDK CPU fallback without repository source imports", async () => {
  const consumerDir = mkdtempSync(join(tmpdir(), "seemcarving-vite-consumer-"));
  let packedTarball;
  let preview;
  let browser;
  let isolatedNpm;

  try {
    cpSync(fixtureDir, consumerDir, { recursive: true });
    isolatedNpm = createIsolatedNpmEnvironment();
    packedTarball = packPackage(isolatedNpm.env);

    execFileSync("npm", ["install", "--ignore-scripts", "--no-save", packedTarball], {
      cwd: consumerDir,
      env: isolatedNpm.env,
      stdio: "inherit",
    });
    execFileSync("npm", ["run", "build"], {
      cwd: consumerDir,
      env: isolatedNpm.env,
      stdio: "inherit",
    });

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
      env: isolatedNpm.env,
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
        isolatedNpm?.cleanup();
        rmSync(consumerDir, { force: true, recursive: true });
      }
    }
  }
});

async function expectCpuFallback(page) {
  assert.equal(await page.locator("#result").getAttribute("data-backend"), "wasm-cpu");
  assert.match(await page.locator("#result").textContent() ?? "", /^Resized with wasm-cpu$/);
}
