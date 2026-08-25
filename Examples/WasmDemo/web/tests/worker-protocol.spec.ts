import { expect, test } from "@playwright/test";

test("CPU path returns wasm-cpu backend with resized dimensions", async ({ page }) => {
  await page.goto("/");
  const result = await page.evaluate(() =>
    window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255, 0, 255, 0, 255]), 2, 1, 1, 1),
  );

  expect(result).toMatchObject({
    type: "success",
    backend: "wasm-cpu",
    jobId: 1,
    width: 1,
    height: 1,
  });
});

test("terminating an active job rejects it and ignores its late response", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
  const cancelled = await page.evaluate(async () => {
    const pending = window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1);
    const outcome = pending.then(
      () => "resolved",
      (error: unknown) => error instanceof DOMException ? error.name : String(error),
    );
    // resize starts in the resolved-ready microtask; terminate only after it
    // has posted an active job to the Worker.
    await Promise.resolve();
    window.__testTerminateActiveWorker!();
    return outcome;
  });
  expect(cancelled).toBe("AbortError");

  await expect(page.getByTestId("worker-status")).toHaveText("ready");
  const replacement = await page.evaluate(async () => {
    const pending = window.__testResizeRGBA8!(new Uint8Array([255, 0, 0, 255]), 1, 1, 1, 1);
    await Promise.resolve();
    window.__testInjectStaleResponse!();
    return pending;
  });
  // The injected job 1 success is a stand-in for a late message from the
  // terminated worker. The new job must remain job 2 and settle normally.
  expect(replacement).toMatchObject({ type: "success", jobId: 2, width: 1, height: 1 });
});
