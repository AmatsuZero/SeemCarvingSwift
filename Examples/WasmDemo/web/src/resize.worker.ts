import { init } from "./generated/index.js";
import type { ResizeRequestMessage } from "./protocol";

const worker = self as DedicatedWorkerGlobalScope;

function isSafePositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0;
}

function isResizeRequest(value: unknown): value is ResizeRequestMessage {
  if (typeof value !== "object" || value === null) return false;
  const message = value as Partial<ResizeRequestMessage>;
  if (
    message.type !== "resize" ||
    typeof message.jobId !== "number" ||
    !Number.isSafeInteger(message.jobId) ||
    message.jobId < 1 ||
    !isSafePositiveInteger(message.sourceWidth) ||
    !isSafePositiveInteger(message.sourceHeight) ||
    !isSafePositiveInteger(message.targetWidth) ||
    !isSafePositiveInteger(message.targetHeight) ||
    !(message.pixels instanceof ArrayBuffer)
  ) return false;

  const sourcePixels = message.sourceWidth * message.sourceHeight;
  return Number.isSafeInteger(sourcePixels) &&
    Number.isSafeInteger(sourcePixels * 4) &&
    message.pixels.byteLength === sourcePixels * 4;
}

// Register before Swift installs `onmessage`, so malformed values never cross
// the JS/WASM boundary. Valid messages continue to Swift's listener.
worker.addEventListener("message", (event: MessageEvent<unknown>) => {
  if (isResizeRequest(event.data)) return;
  event.stopImmediatePropagation();
  const jobId = typeof (event.data as { jobId?: unknown })?.jobId === "number"
    ? (event.data as { jobId: number }).jobId
    : 0;
  worker.postMessage({ type: "failure", jobId, message: "Invalid resize request" });
});

void init().catch((error: unknown) => {
  worker.postMessage({ type: "failure", jobId: 0, message: String(error) });
});
