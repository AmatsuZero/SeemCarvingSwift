import {
  type ResizeFailureMessage,
  type ResizeRequestMessage,
  type ResizeSuccessMessage,
  type WorkerResponseMessage,
} from "./protocol";

export function createResizeWorker(): Worker {
  return new Worker(new URL("./resize.worker.ts", import.meta.url), { type: "module" });
}

type ResizeResult = ResizeSuccessMessage | ResizeFailureMessage;

class ResizeWorkerClient {
  private worker = createResizeWorker();
  private nextJobId = 1;
  private activeJobId: number | undefined;
  private pending:
    | { jobId: number; resolve: (result: ResizeResult) => void; reject: (error: Error) => void }
    | undefined;
  private readyPromise: Promise<void>;
  private resolveReady!: () => void;
  private rejectReady!: (error: Error) => void;
  private readyTimeout: ReturnType<typeof setTimeout> | undefined;

  constructor(private readonly onStatus: (status: "loading" | "ready" | "error") => void) {
    this.readyPromise = new Promise<void>((resolve, reject) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
    this.installWorkerHandlers();
  }

  async resize(
    pixels: Uint8Array,
    sourceWidth: number,
    sourceHeight: number,
    targetWidth: number,
    targetHeight: number,
  ): Promise<ResizeResult> {
    await this.readyPromise;
    if (this.pending) this.cancel();
    const jobId = this.nextJobId++;
    this.activeJobId = jobId;
    const buffer = pixels.buffer.slice(pixels.byteOffset, pixels.byteOffset + pixels.byteLength) as ArrayBuffer;
    const message: ResizeRequestMessage = {
      type: "resize", jobId, pixels: buffer, sourceWidth, sourceHeight, targetWidth, targetHeight,
    };
    return new Promise<ResizeResult>((resolve, reject) => {
      this.pending = { jobId, resolve, reject };
      this.worker.postMessage(message, [buffer]);
    });
  }

  cancel(): void {
    const pending = this.pending;
    this.worker.terminate();
    this.pending = undefined;
    this.activeJobId = undefined;
    pending?.reject(new DOMException("Resize cancelled", "AbortError"));
    this.worker = createResizeWorker();
    this.resetReady();
    this.installWorkerHandlers();
  }

  private resetReady(): void {
    this.onStatus("loading");
    this.readyPromise = new Promise<void>((resolve, reject) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
  }

  private installWorkerHandlers(): void {
    this.readyTimeout = setTimeout(() => this.failInitialization(), 10_000);
    this.worker.onmessage = ({ data }: MessageEvent<WorkerResponseMessage>) => {
      if (data.type === "ready") {
        clearTimeout(this.readyTimeout);
        this.onStatus("ready");
        this.resolveReady();
        return;
      }
      if (data.jobId !== this.activeJobId || !this.pending || data.jobId !== this.pending.jobId) return;
      const pending = this.pending;
      this.pending = undefined;
      this.activeJobId = undefined;
      pending.resolve(data);
    };
    this.worker.onerror = () => this.failInitialization();
  }

  private failInitialization(): void {
    clearTimeout(this.readyTimeout);
    this.onStatus("error");
    this.rejectReady(new Error("WASM worker initialization failed"));
  }
}

const status = document.querySelector<HTMLOutputElement>("[data-testid=worker-status]");
if (!status) throw new Error("Missing worker status output");
const client = new ResizeWorkerClient((value) => { status.textContent = value; });

declare global {
  interface Window {
    __testResizeRGBA8?: (
      pixels: Uint8Array, sourceWidth: number, sourceHeight: number, targetWidth: number, targetHeight: number,
    ) => Promise<ResizeResult>;
    __testTerminateActiveWorker?: () => void;
  }
}

if (import.meta.env.MODE === "test") {
  window.__testResizeRGBA8 = (pixels, sourceWidth, sourceHeight, targetWidth, targetHeight) =>
    client.resize(pixels, sourceWidth, sourceHeight, targetWidth, targetHeight);
  window.__testTerminateActiveWorker = () => client.cancel();
}
