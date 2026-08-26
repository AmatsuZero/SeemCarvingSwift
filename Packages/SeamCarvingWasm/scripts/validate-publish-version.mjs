import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

// npm's stable release channel accepts only complete, non-prerelease SemVer.
const stableVersion = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const tagPrefix = "wasm-v";

export function validatePublishVersion(tag, packageVersion) {
  const tagVersion = tag.startsWith(tagPrefix) ? tag.slice(tagPrefix.length) : "";
  if (!stableVersion.test(tagVersion)) {
    throw new Error(`Tag ${tag || "<missing>"} must contain a stable non-prerelease SemVer version`);
  }
  if (!stableVersion.test(packageVersion)) {
    throw new Error(`Package version ${packageVersion || "<missing>"} must be a stable non-prerelease SemVer version`);
  }
  if (tagVersion !== packageVersion) {
    throw new Error(`Tag ${tag} does not match package version ${packageVersion}`);
  }
}

async function main() {
  const { version } = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
  validatePublishVersion(process.env.GITHUB_REF_NAME ?? "", version);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
