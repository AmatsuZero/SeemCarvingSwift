import { chromium, expect, test } from "@playwright/test";

const pixels = (width: number, height: number, seed: number): Uint8Array =>
  new Uint8Array(Array.from({ length: width * height * 4 }, (_, index) =>
    index % 4 === 3 ? 255 : (index * 31 + seed * 17) % 256));

const fixtures = [
  {
    name: "clamp-to-edge Sobel samples",
    width: 3,
    height: 3,
    targetWidth: 2,
    pixels: new Uint8Array([
      12, 34, 56, 78, 90, 123, 45, 67, 210, 9, 87, 65,
      43, 21, 200, 255, 111, 99, 88, 77, 5, 250, 100, 0,
      200, 150, 100, 50, 25, 75, 125, 175, 225, 175, 125, 75,
    ]),
  },
  {
    // RGB is deliberately 0/255 so its linear luma is exact. The calculated
    // energy rows are [0,0,0,0], [2,2,2,4], [4,2,2,6], making the final
    // costs [6,4,4,8]. Argmin must choose x=1 over x=2, then x=1's actual
    // predecessor candidates x=0,1,2 are tied and must choose the left x=0.
    // Unique alpha markers are ignored by energy but make either bad choice
    // observable in the returned RGBA bytes.
    name: "observable interior parent and final argmin ties",
    width: 4,
    height: 3,
    targetWidth: 3,
    pixels: new Uint8Array([
      0, 0, 0, 10, 0, 0, 0, 20, 0, 0, 0, 30, 0, 0, 0, 40,
      0, 0, 0, 50, 0, 0, 0, 60, 0, 0, 0, 70, 0, 0, 0, 80,
      0, 0, 0, 90, 255, 255, 255, 100, 0, 0, 0, 110, 255, 255, 255, 120,
    ]),
    expectedPixels: [
      0, 0, 0, 20, 0, 0, 0, 30, 0, 0, 0, 40,
      0, 0, 0, 60, 0, 0, 0, 70, 0, 0, 0, 80,
      0, 0, 0, 90, 0, 0, 0, 110, 255, 255, 255, 120,
    ],
  },
  {
    name: "height-one final reduction",
    width: 3,
    height: 1,
    targetWidth: 2,
    pixels: new Uint8Array([0, 0, 0, 1, 128, 128, 128, 2, 255, 255, 255, 3]),
  },
  {
    name: "two-column removal",
    width: 2,
    height: 3,
    targetWidth: 1,
    pixels: new Uint8Array([
      255, 0, 0, 10, 0, 255, 0, 20,
      0, 0, 255, 30, 255, 255, 0, 40,
      255, 0, 255, 50, 0, 255, 255, 60,
    ]),
  },
  {
    name: "three consecutive seams",
    width: 8,
    height: 4,
    targetWidth: 5,
    pixels: pixels(8, 4, 3),
  },
  {
    name: "64 by 32 multi-seam fixture",
    width: 64,
    height: 32,
    targetWidth: 60,
    pixels: pixels(64, 32, 11),
  },
];

test("WebGPU removes backward-Sobel seams with exact WASM CPU parity", async ({ browser }) => {
  // The SDK probes WebGPU inside its Worker, so disabling it in the page alone
  // would not exercise the CPU path. A second Chromium process disables it for
  // both the page and its Worker.
  const cpuBrowser = await chromium.launch({
    args: ["--disable-gpu", "--disable-software-rasterizer"],
  });
  const cpuContext = await cpuBrowser.newContext();
  const cpuPage = await cpuContext.newPage();
  const gpuPage = await browser.newPage();

  try {
    await Promise.all([cpuPage.goto("/"), gpuPage.goto("/")]);
    const webGPUSupported = await gpuPage.evaluate(() => navigator.gpu !== undefined);
    test.skip(!webGPUSupported, "navigator.gpu is unavailable in this Chromium browser");

    for (const fixture of fixtures) {
      const cpu = await cpuPage.evaluate(({ pixels, width, height, targetWidth }) =>
        window.__testResizeRGBA8!(new Uint8Array(pixels), width, height, targetWidth, height), {
        pixels: Array.from(fixture.pixels), width: fixture.width, height: fixture.height, targetWidth: fixture.targetWidth,
      });
      const gpu = await gpuPage.evaluate(({ pixels, width, height, targetWidth }) =>
        window.__testResizeRGBA8!(new Uint8Array(pixels), width, height, targetWidth, height), {
        pixels: Array.from(fixture.pixels), width: fixture.width, height: fixture.height, targetWidth: fixture.targetWidth,
      });

      expect(cpu.backend, fixture.name).toBe("wasm-cpu");
      expect(gpu.backend, fixture.name).toBe("webgpu");
      if (fixture.expectedPixels) expect(Array.from(cpu.pixels), fixture.name).toEqual(fixture.expectedPixels);
      expect(Array.from(gpu.pixels), fixture.name).toEqual(Array.from(cpu.pixels));
    }
  } finally {
    await cpuContext.close();
    await cpuBrowser.close();
    await gpuPage.close();
  }
});
