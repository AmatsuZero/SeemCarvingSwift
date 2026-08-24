import { init } from "./generated/index.js";

void init().catch((error: unknown) => {
  self.postMessage({ type: "error", message: String(error) });
});
