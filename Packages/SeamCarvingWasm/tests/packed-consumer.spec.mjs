import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
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

test("a Vite app builds from the packed SDK without repository source imports", () => {
  const consumerDir = mkdtempSync(join(tmpdir(), "seemcarving-vite-consumer-"));
  let packedTarball;

  try {
    cpSync(fixtureDir, consumerDir, { recursive: true });
    packedTarball = packPackage();

    execFileSync("npm", ["install", "--no-save", packedTarball], {
      cwd: consumerDir,
      stdio: "inherit",
    });
    execFileSync("npm", ["run", "build"], { cwd: consumerDir, stdio: "inherit" });

    assert.ok(existsSync(join(consumerDir, "dist", "assets")));
    assert.notEqual(
      realpathSync(join(consumerDir, "node_modules", "@seemcarving", "wasm")),
      realpathSync(packageDir),
      "the consumer must install a tarball rather than link the repository package",
    );

    const assetDir = join(consumerDir, "dist", "assets");
    const bundledScripts = readdirSync(assetDir, { recursive: true })
      .filter((entry) => entry.endsWith(".js"))
      .map((entry) => readFileSync(join(assetDir, entry), "utf8"));
    assert.ok(bundledScripts.length > 0, "Vite must emit JavaScript assets");
    assert.doesNotMatch(bundledScripts.join("\n"), /SeamCarvingWasm\/src/);
  } finally {
    if (packedTarball) rmSync(packedTarball, { force: true });
    rmSync(consumerDir, { force: true, recursive: true });
  }
});
