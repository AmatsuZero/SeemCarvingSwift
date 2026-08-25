import { chromium, expect, test } from "@playwright/test";

const fixtures = [
  {
    name: "clamp-to-edge Sobel samples",
    width: 3,
    height: 3,
    pixels: new Uint8Array([
      12, 34, 56, 78, 90, 123, 45, 67, 210, 9, 87, 65,
      43, 21, 200, 255, 111, 99, 88, 77, 5, 250, 100, 0,
      200, 150, 100, 50, 25, 75, 125, 175, 225, 175, 125, 75,
    ]),
  },
  {
    name: "parent and final argmin ties",
    width: 3,
    height: 3,
    pixels: new Uint8Array(Array.from({ length: 9 }, () => [64, 64, 64, 255]).flat()),
  },
  {
    name: "height-one final reduction",
    width: 3,
    height: 1,
    pixels: new Uint8Array([0, 0, 0, 1, 128, 128, 128, 2, 255, 255, 255, 3]),
  },
  {
    name: "two-column removal",
    width: 2,
    height: 3,
    pixels: new Uint8Array([
      255, 0, 0, 10, 0, 255, 0, 20,
      0, 0, 255, 30, 255, 255, 0, 40,
      255, 0, 255, 50, 0, 255, 255, 60,
    ]),
  },
];

test("WebGPU removes the same backward-Sobel seam as the WASM CPU", async ({ browser }) => {
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
      const cpu = await cpuPage.evaluate(({ pixels, width, height }) =>
        window.__testResizeRGBA8!(new Uint8Array(pixels), width, height, width - 1, height), {
        pixels: Array.from(fixture.pixels), width: fixture.width, height: fixture.height,
      });
      const gpu = await gpuPage.evaluate(({ pixels, width, height }) =>
        window.__testResizeRGBA8!(new Uint8Array(pixels), width, height, width - 1, height), {
        pixels: Array.from(fixture.pixels), width: fixture.width, height: fixture.height,
      });

      expect(cpu.backend, fixture.name).toBe("wasm-cpu");
      expect(gpu.backend, fixture.name).toBe("webgpu");
      expect(Array.from(gpu.pixels), fixture.name).toEqual(Array.from(cpu.pixels));
    }
  } finally {
    await cpuContext.close();
    await cpuBrowser.close();
    await gpuPage.close();
  }
});
