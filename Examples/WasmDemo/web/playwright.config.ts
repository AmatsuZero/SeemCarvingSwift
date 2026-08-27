import { defineConfig } from "@playwright/test";
import { existsSync } from "node:fs";

// Playwright's bundled browser is used by default (and always in CI).  Local
// macOS runs can opt into the installed Google Chrome app when the matching
// Playwright headless shell has not been downloaded yet.
const localChromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const localChromium =
  process.platform === "darwin" && !process.env.CI && existsSync(localChromePath)
    ? { channel: "chrome" }
    : {};
const previewURL = "http://127.0.0.1:4174";

export default defineConfig({
  testDir: "./tests",
  // The Swift/WASM runtime is deliberately loaded in a module Worker. Even
  // after wasm-opt, its first compilation can take longer than Playwright's
  // 5-second assertion default on Firefox/WebKit CI runners. Keep readiness
  // mandatory, but give the browser a bounded, realistic cold-start budget.
  timeout: 90_000,
  expect: { timeout: 60_000 },
  webServer: {
    command: "npm run build -- --mode test && npm run preview -- --host 127.0.0.1 --port 4174",
    url: previewURL,
    reuseExistingServer: !process.env.CI,
  },
  use: { baseURL: previewURL },
  projects: [
    { name: "chromium", use: { browserName: "chromium", ...localChromium } },
    { name: "firefox", use: { browserName: "firefox" } },
    { name: "webkit", use: { browserName: "webkit" } },
  ],
});
