import { cp, readdir, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const artifactDir = path.resolve(
  packageDir,
  "../../Examples/WasmDemo/swift/.build/plugins/PackageToJS/outputs/Package",
);
const generatedDir = path.join(packageDir, "src/generated");

async function hasWasmFile(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory() && await hasWasmFile(entryPath)) return true;
    if (entry.isFile() && entry.name.endsWith(".wasm")) return true;
  }
  return false;
}

await rm(generatedDir, { force: true, recursive: true });

try {
  try {
    if (!(await stat(artifactDir)).isDirectory()) {
      throw new Error("not a directory");
    }
  } catch {
    throw new Error(`PackageToJS artifact directory is missing: ${artifactDir}`);
  }

  await cp(artifactDir, generatedDir, { recursive: true });

  const entryLoader = path.join(generatedDir, "index.js");
  try {
    if (!(await stat(entryLoader)).isFile()) {
      throw new Error("not a file");
    }
  } catch {
    throw new Error(`PackageToJS entry loader is missing: ${entryLoader}`);
  }

  if (!await hasWasmFile(generatedDir)) {
    throw new Error(`PackageToJS artifact does not contain a WASM module: ${artifactDir}`);
  }
} catch (error) {
  await rm(generatedDir, { force: true, recursive: true });
  throw error;
}
