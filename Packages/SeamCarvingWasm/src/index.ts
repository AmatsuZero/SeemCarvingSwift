import { WorkerSeamCarver, type CreateSeamCarverOptions } from "./client.js";
import type { BackendIdentifier } from "./protocol.js";

export type { CreateSeamCarverOptions } from "./client.js";
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

export async function createSeamCarver(options: CreateSeamCarverOptions = {}): Promise<SeamCarver> {
  const carver = new WorkerSeamCarver(
    options.worker ?? new Worker(new URL("./worker.js", import.meta.url), { type: "module" }),
  );
  await carver.waitUntilReady();
  return carver;
}
