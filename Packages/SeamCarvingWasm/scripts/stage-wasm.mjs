import { cp, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const artifactDir = path.resolve(
  packageDir,
  "../../Examples/WasmDemo/swift/.build/plugins/PackageToJS/outputs/Package",
);
const generatedDir = path.join(packageDir, "src/generated");
const requiredRuntimeFiles = [
  "WasmBridgeWorker.wasm",
  "index.js",
  "instantiate.js",
  "runtime.js",
  "platforms/browser.js",
  "platforms/browser.worker.js",
  "platforms/node.js",
];

async function requireFile(relativePath) {
  const filePath = path.join(generatedDir, relativePath);
  try {
    if (!(await stat(filePath)).isFile()) throw new Error("not a file");
  } catch {
    throw new Error(`PackageToJS runtime file is missing: ${filePath}`);
  }
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

  for (const relativePath of requiredRuntimeFiles) {
    await requireFile(relativePath);
  }
} catch (error) {
  await rm(generatedDir, { force: true, recursive: true });
  throw error;
}
