import { expect, test } from "@playwright/test";

test("worker returns the same job ID and resized dimensions", async ({ page }) => {
  await page.goto("/");
  const result = await page.evaluate(() =>
    window.__testResizeRGBA8(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1),
  );

  expect(result).toMatchObject({ type: "success", jobId: 1, width: 1, height: 1 });
});

test("terminating a job recreates a ready worker", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => window.__testTerminateActiveWorker());
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
});
