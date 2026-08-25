import type { BackendIdentifier } from "./protocol.js";

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

/**
 * Creates a seam carver once the Worker client is installed in the next SDK step.
 */
export async function createSeamCarver(): Promise<SeamCarver> {
  throw new Error("Worker client not installed");
}
