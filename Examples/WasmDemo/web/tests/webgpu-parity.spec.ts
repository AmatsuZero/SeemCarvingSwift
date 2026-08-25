import { chromium, expect, test } from "@playwright/test";

const fixture = new Uint8Array([
  12, 34, 56, 78,  90, 123, 45, 67,  210, 9, 87, 65,
  43, 21, 200, 255,  111, 99, 88, 77,  5, 250, 100, 0,
  200, 150, 100, 50,  25, 75, 125, 175,  225, 175, 125, 75,
]);

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

    const cpu = await cpuPage.evaluate((pixels) =>
      window.__testResizeRGBA8!(new Uint8Array(pixels), 3, 3, 2, 3), Array.from(fixture));
    const gpu = await gpuPage.evaluate((pixels) =>
      window.__testResizeRGBA8!(new Uint8Array(pixels), 3, 3, 2, 3), Array.from(fixture));

    expect(cpu.backend).toBe("wasm-cpu");
    expect(gpu.backend).toBe("webgpu");
    expect(Array.from(gpu.pixels)).toEqual(Array.from(cpu.pixels));
  } finally {
    await cpuContext.close();
    await cpuBrowser.close();
    await gpuPage.close();
  }
});
