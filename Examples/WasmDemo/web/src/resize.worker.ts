import { init } from "./generated/index.js";
import type { ResizeRequestMessage, ResizeResponseMessage } from "./protocol";

const worker = self as DedicatedWorkerGlobalScope;
type WasmResizeGlobal = DedicatedWorkerGlobalScope & {
  __seamCarvingWasmResize?: (request: ResizeRequestMessage) => Promise<ResizeResponseMessage>;
};

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

function postFailure(jobId: number, error: unknown): void {
  worker.postMessage({ type: "failure", jobId, message: String(error) });
}

void init().then(() => {
  const wasmResize = (worker as WasmResizeGlobal).__seamCarvingWasmResize;
  if (!wasmResize) throw new Error("WASM CPU resize callable is unavailable");

  worker.onmessage = (event: MessageEvent<unknown>) => {
    const { data } = event;
    const jobId = typeof (data as { jobId?: unknown })?.jobId === "number"
      ? (data as { jobId: number }).jobId
      : 0;
    if (!isResizeRequest(data)) {
      postFailure(jobId, "Invalid resize request");
      return;
    }

    void wasmResize(data).then(
      (response) => worker.postMessage(response, [response.pixels]),
      (error: unknown) => postFailure(data.jobId, error),
    );
  };
}).catch((error: unknown) => {
  postFailure(0, error);
});
