import type { ResizeRequest, ResizeResult, SeamCarver } from "./index.js";
import type {
  ResizeRequestMessage,
  ResizeSuccessMessage,
  WorkerResponseMessage,
} from "./protocol.js";

export interface CreateSeamCarverOptions {
  /** Supply a Worker when embedding or testing the SDK. */
  worker?: Worker;
}

type PendingResize = {
  jobId: number;
  resolve: (result: ResizeResult) => void;
  reject: (error: Error) => void;
};

export class WorkerSeamCarver implements SeamCarver {
  private nextJobId = 1;
  private pending: PendingResize | undefined;
  private terminated = false;

  constructor(private readonly worker: Worker) {
    worker.onmessage = (event: MessageEvent<WorkerResponseMessage>) => this.handleMessage(event.data);
    worker.onerror = () => this.failPending(new Error("WASM worker failed"));
  }

  resize(request: ResizeRequest): Promise<ResizeResult> {
    if (this.terminated) return Promise.reject(new Error("Seam carver has been terminated"));
    if (this.pending) return Promise.reject(new Error("A resize is already in progress"));

    const pixels = request.pixels.buffer.slice(
      request.pixels.byteOffset,
      request.pixels.byteOffset + request.pixels.byteLength,
    ) as ArrayBuffer;
    const jobId = this.nextJobId++;
    const message: ResizeRequestMessage = {
      type: "resize",
      jobId,
      pixels,
      sourceWidth: request.width,
      sourceHeight: request.height,
      targetWidth: request.targetWidth,
      targetHeight: request.targetHeight,
    };

    return new Promise<ResizeResult>((resolve, reject) => {
      this.pending = { jobId, resolve, reject };
      try {
        this.worker.postMessage(message, [pixels]);
      } catch (error) {
        this.failPending(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  terminate(): void {
    if (this.terminated) return;
    this.terminated = true;
    this.worker.terminate();
    this.failPending(new Error("Seam carver has been terminated"));
  }

  private handleMessage(message: WorkerResponseMessage): void {
    if (message.type === "ready" || !this.pending || message.jobId !== this.pending.jobId) return;

    const pending = this.pending;
    this.pending = undefined;
    if (message.type === "failure") {
      pending.reject(new Error(message.message));
      return;
    }
    pending.resolve(this.toResizeResult(message));
  }

  private toResizeResult(message: ResizeSuccessMessage): ResizeResult {
    return {
      backend: message.backend,
      width: message.width,
      height: message.height,
      pixels: new Uint8Array(message.pixels),
    };
  }

  private failPending(error: Error): void {
    const pending = this.pending;
    this.pending = undefined;
    pending?.reject(error);
  }
}
