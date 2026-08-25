import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

test("packed package contains the runtime and type assets", () => {
  const packed = JSON.parse(
    execFileSync("npm", ["pack", "--json"], { cwd: packageDir, encoding: "utf8" }),
  );
  const { filename } = Array.isArray(packed) ? packed[0] : Object.values(packed)[0];

  try {
    const files = execFileSync("tar", ["-tf", filename], {
      cwd: packageDir,
      encoding: "utf8",
    });

    for (const name of [
      "package/dist/index.js",
      "package/dist/worker.js",
      "package/dist/WasmBridgeWorker.wasm",
      "package/dist/index.d.ts",
    ]) {
      assert.match(files, new RegExp(`^${name}$`, "m"));
    }

    for (const name of files.trim().split("\n")) {
      assert.match(name, /^package\/(?:dist\/.+|README\.md|LICENSE|package\.json)$/);
    }
  } finally {
    rmSync(path.join(packageDir, filename), { force: true });
  }
});
