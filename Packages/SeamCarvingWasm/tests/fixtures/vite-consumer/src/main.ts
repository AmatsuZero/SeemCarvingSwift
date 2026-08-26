import { createSeamCarver } from "@seemcarving/wasm";

const output = document.querySelector<HTMLOutputElement>("#result");
if (!output) throw new Error("Missing resize result output");

async function resizeWithCpuFallback(): Promise<void> {
  const carver = await createSeamCarver();
  try {
    const result = await carver.resize({
      pixels: new Uint8Array([
        255, 0, 0, 255,
        0, 0, 255, 255,
      ]),
      width: 2,
      height: 1,
      targetWidth: 1,
      targetHeight: 1,
    });

    if (result.width !== 1 || result.height !== 1 || result.pixels.byteLength !== 4) {
      throw new Error("Unexpected 2×1 → 1×1 resize result");
    }
    output.textContent = `Resized with ${result.backend}`;
  } finally {
    carver.terminate();
  }
}

void resizeWithCpuFallback().catch((error: unknown) => {
  output.textContent = error instanceof Error ? error.message : String(error);
});
