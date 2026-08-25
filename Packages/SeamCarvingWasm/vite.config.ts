import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Plugin } from "vite";
import { defineConfig } from "vite";

const generatedDir = resolve(import.meta.dirname, "src/generated");

async function generatedRuntimeFiles(directory = generatedDir, relativePath = ""): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryRelativePath = relativePath ? `${relativePath}/${entry.name}` : entry.name;
    const entryPath = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await generatedRuntimeFiles(entryPath, entryRelativePath));
    } else if (entry.isFile() && (entry.name.endsWith(".js") || entry.name.endsWith(".wasm"))) {
      files.push(entryRelativePath);
    }
  }
  return files;
}

/**
 * PackageToJS resolves its runtime modules and WASM file relative to index.js.
 * Keep those files byte-for-byte in dist rather than allowing library mode to
 * inline or rename their URLs. Task 3 replaces the loader export with the SDK
 * Worker implementation.
 */
function preservePackageToJSRuntime(): Plugin {
  return {
    name: "preserve-package-to-js-runtime",
    async generateBundle() {
      for (const relativePath of await generatedRuntimeFiles()) {
        this.emitFile({
          fileName: relativePath === "index.js" ? "worker.js" : relativePath,
          source: await readFile(resolve(generatedDir, relativePath)),
          type: "asset",
        });
      }
    },
  };
}

export default defineConfig({
  plugins: [preservePackageToJSRuntime()],
  test: {
    passWithNoTests: true,
    exclude: ["tests/package-contents.spec.mjs"],
  },
  build: {
    emptyOutDir: false,
    lib: {
      entry: resolve(import.meta.dirname, "src/index.ts"),
      formats: ["es"],
      fileName: () => "index.js",
    },
    rollupOptions: {
      output: {
        assetFileNames: "[name][extname]",
      },
    },
  },
});
