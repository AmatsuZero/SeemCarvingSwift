import { expect, test } from "@playwright/test";

const fixtures = {
  png: "tests/fixtures/rgba-2x1.png",
  jpeg: "tests/fixtures/oriented-3x2.jpg",
};

test("uploads a PNG, preserves exact RGBA bytes, and downloads PNG", async ({ page }) => {
  await page.goto("/");
  await page.locator("#source-file").setInputFiles(fixtures.png);
  await expect(page.locator("#source-canvas")).toHaveAttribute("width", "2");
  await expect(page.locator("#source-canvas")).toHaveAttribute("height", "1");

  await page.locator("#target-width").fill("2");
  await page.locator("#target-height").fill("1");
  await page.getByRole("button", { name: "Resize" }).click();

  await expect(page.locator("#result-canvas")).toHaveAttribute("width", "2");
  await expect(page.locator("#result-canvas")).toHaveAttribute("height", "1");
  await expect(page.getByRole("button", { name: "Download PNG" })).toBeEnabled();
  await expect(page.locator("#status")).toContainText("Resize complete");

  const pixels = await page.locator("#result-canvas").evaluate((canvas) =>
    Array.from((canvas as HTMLCanvasElement).getContext("2d")!.getImageData(0, 0, 2, 1).data),
  );
  expect(pixels).toEqual([255, 0, 0, 255, 0, 255, 0, 128]);

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Download PNG" }).click();
  const download = await downloadPromise;
  const bytes = await download.createReadStream().then(async (stream) => {
    const chunks: Buffer[] = [];
    for await (const chunk of stream!) chunks.push(chunk as Buffer);
    return Buffer.concat(chunks);
  });
  expect([...bytes.subarray(0, 8)]).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
});

test("uses ImageBitmap EXIF orientation while decoding JPEG", async ({ page }) => {
  await page.goto("/");
  await page.locator("#source-file").setInputFiles(fixtures.jpeg);
  await expect(page.locator("#source-canvas")).toHaveAttribute("width", "2");
  await expect(page.locator("#source-canvas")).toHaveAttribute("height", "3");

  // JPEG is lossy. With quality 100 and no chroma subsampling, EXIF rotation
  // moves the source bottom-left yellow pixel to the displayed top-left within
  // four byte values per channel.
  const pixel = await page.locator("#source-canvas").evaluate((canvas) =>
    Array.from((canvas as HTMLCanvasElement).getContext("2d")!.getImageData(0, 0, 1, 1).data),
  );
  expect(Math.abs(pixel[0] - 255)).toBeLessThanOrEqual(4);
  expect(Math.abs(pixel[1] - 255)).toBeLessThanOrEqual(4);
  expect(Math.abs(pixel[2] - 0)).toBeLessThanOrEqual(4);
  expect(pixel[3]).toBe(255);
});

test("reports an invalid target and focuses the live status", async ({ page }) => {
  await page.goto("/");
  await page.locator("#source-file").setInputFiles(fixtures.png);
  await page.locator("#target-width").fill("0");

  await expect(page.getByRole("button", { name: "Resize" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "Download PNG" })).toBeDisabled();
});
