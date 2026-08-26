import { WorkerSeamCarver, type CreateSeamCarverOptions } from "./client.js";
import type { BackendIdentifier } from "./protocol.js";

export type { CreateSeamCarverOptions, WorkerFactory } from "./client.js";
export type { BackendIdentifier } from "./protocol.js";

export interface ResizeRequest {
  pixels: Uint8Array;
  width: number;
  height: number;
  targetWidth: number;
  targetHeight: number;
}

export interface ResizeResult {
  pixels: Uint8Array;
  width: number;
  height: number;
  backend: BackendIdentifier;
}

export interface SeamCarver {
  resize(request: ResizeRequest): Promise<ResizeResult>;
  terminate(): void;
}

/** Creates the SDK's default module Worker. */
export function createWorker(): Worker {
  return new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
}

export async function createSeamCarver(options: CreateSeamCarverOptions = {}): Promise<SeamCarver> {
  const carver = new WorkerSeamCarver(options.worker ?? options.workerFactory?.() ?? createWorker());
  const abort = () => carver.terminate();
  const { signal } = options;

  if (signal?.aborted) {
    abort();
  } else {
    signal?.addEventListener("abort", abort, { once: true });
  }

  try {
    await carver.waitUntilReady();
    if (signal?.aborted) throw new Error("Seam carver has been terminated");
    return carver;
  } finally {
    signal?.removeEventListener("abort", abort);
  }
}
