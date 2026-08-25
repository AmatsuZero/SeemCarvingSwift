import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { Plugin } from "vite";
import { defineConfig } from "vite";

const packageRoot = import.meta.dirname;
const generatedDir = resolve(packageRoot, "src/generated");

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

/** Keep PackageToJS modules and its WASM binary relative to the SDK worker. */
function preservePackageToJSRuntime(): Plugin {
  return {
    name: "preserve-package-to-js-runtime",
    async generateBundle() {
      for (const relativePath of await generatedRuntimeFiles()) {
        this.emitFile({
          fileName: `generated/${relativePath}`,
          source: await readFile(resolve(generatedDir, relativePath)),
          type: "asset",
        });
      }
    },
  };
}

const generatedIndex = "./generated/index.js";

export default defineConfig({
  base: "./",
  plugins: [preservePackageToJSRuntime()],
  test: {
    passWithNoTests: true,
    exclude: ["tests/package-contents.spec.mjs"],
  },
  worker: {
    format: "es",
    rollupOptions: {
      external: (id) => id === generatedIndex,
      output: { entryFileNames: "worker.js" },
    },
  },
  build: {
    emptyOutDir: false,
    lib: {
      entry: resolve(packageRoot, "src/index.ts"),
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
