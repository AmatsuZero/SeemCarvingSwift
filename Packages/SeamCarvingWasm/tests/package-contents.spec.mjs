import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const expectedFiles = new Set([
  "package/README.md",
  "package/package.json",
  "package/dist/index.d.ts",
  "package/dist/protocol.d.ts",
  "package/dist/index.js",
  "package/dist/worker.js",
  "package/dist/WasmBridgeWorker.wasm",
  "package/dist/instantiate.js",
  "package/dist/runtime.js",
  "package/dist/platforms/browser.js",
  "package/dist/platforms/browser.worker.js",
  "package/dist/platforms/node.js",
]);

test("packed package contains exactly the public API and PackageToJS runtime", () => {
  const packed = JSON.parse(
    execFileSync("npm", ["pack", "--json"], { cwd: packageDir, encoding: "utf8" }),
  );
  const { filename } = Array.isArray(packed) ? packed[0] : Object.values(packed)[0];

  try {
    const files = execFileSync("tar", ["-tf", filename], {
      cwd: packageDir,
      encoding: "utf8",
    }).trim().split("\n");

    assert.deepEqual(new Set(files), expectedFiles);
  } finally {
    rmSync(path.join(packageDir, filename), { force: true });
  }
});
