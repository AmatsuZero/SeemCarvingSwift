import { expect, test } from "@playwright/test";

test("CPU path returns wasm-cpu backend with resized dimensions", async ({ page }) => {
  await page.goto("/");
  const result = await page.evaluate(() =>
    window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255, 0, 255, 0, 255]), 2, 1, 1, 1),
  );

  expect(result).toMatchObject({
    backend: "wasm-cpu",
    width: 1,
    height: 1,
  });
});

test("terminating an active job rejects it and a replacement client can resize", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
  const cancelled = await page.evaluate(async () => {
    const pending = window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1);
    await Promise.resolve();
    window.__testTerminateActiveWorker!();
    return pending.then(
      () => "resolved",
      (error: unknown) => error instanceof Error ? error.message : String(error),
    );
  });
  expect(cancelled).toContain("terminated");

  await expect(page.getByTestId("worker-status")).toHaveText("ready");
  const replacement = await page.evaluate(() =>
    window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1),
  );
  expect(replacement).toMatchObject({ backend: "wasm-cpu", width: 1, height: 1 });
});
