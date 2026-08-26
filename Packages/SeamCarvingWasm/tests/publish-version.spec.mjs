import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validatePublishVersion } from "../scripts/validate-publish-version.mjs";

test("accepts matching stable WASM release versions", () => {
  assert.doesNotThrow(() => validatePublishVersion("wasm-v0.1.0", "0.1.0"));
});

test("rejects matching prerelease tag and package versions", () => {
  assert.throws(
    () => validatePublishVersion("wasm-v0.1.0-beta.1", "0.1.0-beta.1"),
    /stable non-prerelease SemVer/,
  );
});

test("rejects a prerelease package version even with a stable tag", () => {
  assert.throws(
    () => validatePublishVersion("wasm-v0.1.0", "0.1.0-beta.1"),
    /stable non-prerelease SemVer/,
  );
});

test("publication workflow runs the shared stable-version validator", async () => {
  const workflow = await readFile(
    fileURLToPath(new URL("../../../.github/workflows/publish-npm.yml", import.meta.url)),
    "utf8",
  );

  assert.match(workflow, /run: node scripts\/validate-publish-version\.mjs/);
});
