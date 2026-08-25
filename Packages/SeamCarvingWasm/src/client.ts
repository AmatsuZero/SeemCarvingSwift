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

type LifecycleState = "initializing" | "ready" | "failed" | "terminated";

export class WorkerSeamCarver implements SeamCarver {
  private nextJobId = 1;
  private pending: PendingResize | undefined;
  private state: LifecycleState = "initializing";
  private failure: Error | undefined;
  private readonly readyPromise: Promise<void>;
  private resolveReady!: () => void;
  private rejectReady!: (error: Error) => void;

  constructor(private readonly worker: Worker) {
    this.readyPromise = new Promise<void>((resolve, reject) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
    worker.onmessage = (event: MessageEvent<WorkerResponseMessage>) => this.handleMessage(event.data);
    worker.onerror = () => this.failTerminal(new Error("WASM worker failed"));
  }

  async waitUntilReady(): Promise<void> {
    await this.readyPromise;
  }

  resize(request: ResizeRequest): Promise<ResizeResult> {
    if (this.state !== "ready") return Promise.reject(this.unavailableError());
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
        this.failTerminal(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  terminate(): void {
    if (this.state === "terminated" || this.state === "failed") return;
    this.state = "terminated";
    const error = new Error("Seam carver has been terminated");
    this.worker.terminate();
    this.failPending(error);
    this.rejectReady(error);
  }

  private handleMessage(message: WorkerResponseMessage): void {
    if (message.type === "ready") {
      if (this.state === "initializing" && message.ready === true) {
        this.state = "ready";
        this.resolveReady();
      }
      return;
    }

    if (message.type === "failure" && message.jobId === 0) {
      this.failTerminal(new Error(message.message));
      return;
    }

    if (this.state !== "ready" || !this.pending || message.jobId !== this.pending.jobId) return;

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

  private failTerminal(error: Error): void {
    if (this.state === "failed" || this.state === "terminated") return;
    const wasInitializing = this.state === "initializing";
    this.state = "failed";
    this.failure = error;
    this.worker.terminate();
    this.failPending(error);
    if (wasInitializing) this.rejectReady(error);
  }

  private unavailableError(): Error {
    if (this.state === "failed") return this.failure ?? new Error("WASM worker failed");
    if (this.state === "terminated") return new Error("Seam carver has been terminated");
    return new Error("WASM worker has not initialized");
  }

  private failPending(error: Error): void {
    const pending = this.pending;
    this.pending = undefined;
    pending?.reject(error);
  }
}
