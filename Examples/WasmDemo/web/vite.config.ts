import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Plugin } from "vite";
import { defineConfig } from "vite";

const packageRuntimeDir = resolve(
  import.meta.dirname,
  "node_modules/@seemcarving/wasm/dist/generated",
);

async function runtimeFiles(directory = packageRuntimeDir, relativePath = ""): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryRelativePath = relativePath ? `${relativePath}/${entry.name}` : entry.name;
    const entryPath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await runtimeFiles(entryPath, entryRelativePath));
    } else if (entry.isFile()) {
      files.push(entryRelativePath);
    }
  }
  return files;
}

/**
 * Vite emits the SDK Worker next to the app bundle. Copy the unbundled
 * PackageToJS runtime beside that Worker so its relative module and WASM URLs
 * remain valid in the consuming application.
 */
function copySdkRuntime(): Plugin {
  return {
    name: "copy-seam-carving-sdk-runtime",
    async generateBundle() {
      for (const relativePath of await runtimeFiles()) {
        this.emitFile({
          fileName: `assets/generated/${relativePath}`,
          source: await readFile(resolve(packageRuntimeDir, relativePath)),
          type: "asset",
        });
      }
    },
  };
}

export default defineConfig({
  plugins: [copySdkRuntime()],
  build: {
    // Keep the SDK Worker as a file: its runtime imports remain relative.
    assetsInlineLimit: 0,
  },
});
