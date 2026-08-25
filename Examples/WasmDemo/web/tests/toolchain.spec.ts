import { expect, test } from "@playwright/test";

test("generated Swift WASM worker announces readiness", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("worker-status")).toHaveText("ready");
});
