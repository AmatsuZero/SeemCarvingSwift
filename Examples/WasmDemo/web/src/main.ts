import "./styles.css";
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

  resize(
    pixels: Uint8Array,
    sourceWidth: number,
    sourceHeight: number,
    targetWidth: number,
    targetHeight: number,
  ): Promise<ResizeResult> {
    return this.readyPromise.then(() => {
      if (this.pending) {
        this.cancel();
        return this.resize(pixels, sourceWidth, sourceHeight, targetWidth, targetHeight);
      }
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
    });
  }

  cancel(): void {
    const pending = this.pending;
    clearTimeout(this.readyTimeout);
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
    const installedWorker = this.worker;
    this.worker.onmessage = ({ data }: MessageEvent<WorkerResponseMessage>) => {
      if (this.worker === installedWorker) this.handleMessage(data);
    };
    this.worker.onerror = () => {
      if (this.worker === installedWorker) this.failInitialization();
    };
  }

  private handleMessage(data: WorkerResponseMessage): void {
    if (data.type === "ready") {
      clearTimeout(this.readyTimeout);
      this.onStatus("ready");
      this.resolveReady();
      return;
    }
    // A terminated worker can still have an already-queued message. Only the
    // currently active job is allowed to settle the current promise.
    if (data.jobId !== this.activeJobId || !this.pending || data.jobId !== this.pending.jobId) return;
    const pending = this.pending;
    this.pending = undefined;
    this.activeJobId = undefined;
    pending.resolve(data);
  }

  injectStaleResponseForTest(): void {
    this.handleMessage({ type: "success", jobId: 1, width: 1, height: 1, pixels: new ArrayBuffer(4) });
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
    __testInjectStaleResponse?: () => void;
  }
}

if (import.meta.env.MODE === "test") {
  window.__testResizeRGBA8 = (pixels, sourceWidth, sourceHeight, targetWidth, targetHeight) =>
    client.resize(pixels, sourceWidth, sourceHeight, targetWidth, targetHeight);
  window.__testTerminateActiveWorker = () => client.cancel();
  window.__testInjectStaleResponse = () => client.injectStaleResponseForTest();
}


type ImageState = {
  pixels: Uint8ClampedArray;
  width: number;
  height: number;
};

const pixelLimit = 2_000_000;
const workLimit = 80_000_000;

function requiredElement<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing required element: ${selector}`);
  return element;
}

const sourceFile = requiredElement<HTMLInputElement>("#source-file");
const targetWidth = requiredElement<HTMLInputElement>("#target-width");
const targetHeight = requiredElement<HTMLInputElement>("#target-height");
const resizeButton = requiredElement<HTMLButtonElement>("#resize");
const cancelButton = requiredElement<HTMLButtonElement>("#cancel");
const downloadButton = requiredElement<HTMLButtonElement>("#download");
const appStatus = requiredElement<HTMLElement>("#status");
const sourceCanvas = requiredElement<HTMLCanvasElement>("#source-canvas");
const resultCanvas = requiredElement<HTMLCanvasElement>("#result-canvas");
const sourceDimensions = requiredElement<HTMLElement>("#source-dimensions");
const resultDimensions = requiredElement<HTMLElement>("#result-dimensions");
const sourceContext = sourceCanvas.getContext("2d", { willReadFrequently: true });
const resultContext = resultCanvas.getContext("2d");
if (!sourceContext || !resultContext) throw new Error("Canvas 2D is unavailable");

let source: ImageState | undefined;
let result: ImageState | undefined;
let isRunning = false;

function setStatus(message: string, focus = false): void {
  appStatus.textContent = message;
  if (focus) appStatus.focus();
}

function positiveInteger(input: HTMLInputElement): number | undefined {
  const value = Number(input.value);
  return Number.isSafeInteger(value) && value > 0 ? value : undefined;
}

function checkedPixelCount(width: number, height: number): number | undefined {
  const pixels = width * height;
  return Number.isSafeInteger(pixels) ? pixels : undefined;
}

function validationMessage(): string | undefined {
  if (!source) return "Choose a PNG or JPEG image first.";
  const sourcePixels = checkedPixelCount(source.width, source.height);
  if (!sourcePixels || sourcePixels > pixelLimit) return "Source image must contain at most 2,000,000 pixels.";

  const width = positiveInteger(targetWidth);
  const height = positiveInteger(targetHeight);
  if (!width || !height) return "Target width and height must be positive whole numbers.";
  const targetPixels = checkedPixelCount(width, height);
  if (!targetPixels || targetPixels > pixelLimit) return "Target image must contain at most 2,000,000 pixels.";

  const work = Math.abs(source.width - width) * source.height + Math.abs(source.height - height) * width;
  if (!Number.isSafeInteger(work) || work > workLimit) return "Requested resize exceeds the 80,000,000 pixel-work limit.";
  return undefined;
}

function updateControls(): void {
  const valid = validationMessage() === undefined;
  resizeButton.disabled = isRunning || !valid;
  cancelButton.disabled = !isRunning;
  downloadButton.disabled = isRunning || !result;
}

function clearResult(): void {
  result = undefined;
  resultCanvas.width = 1;
  resultCanvas.height = 1;
  resultDimensions.textContent = "—";
}

async function decodeSource(file: File): Promise<void> {
  if (file.type !== "image/png" && file.type !== "image/jpeg") {
    throw new Error("Choose a PNG or JPEG image.");
  }
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  try {
    const pixels = checkedPixelCount(bitmap.width, bitmap.height);
    if (!pixels || pixels > pixelLimit) throw new Error("Source image must contain at most 2,000,000 pixels.");
    sourceCanvas.width = bitmap.width;
    sourceCanvas.height = bitmap.height;
    sourceContext.clearRect(0, 0, bitmap.width, bitmap.height);
    sourceContext.drawImage(bitmap, 0, 0);
    const imageData = sourceContext.getImageData(0, 0, bitmap.width, bitmap.height);
    source = { pixels: imageData.data, width: bitmap.width, height: bitmap.height };
    sourceDimensions.textContent = `${bitmap.width} × ${bitmap.height}`;
    targetWidth.value = String(bitmap.width);
    targetHeight.value = String(bitmap.height);
  } finally {
    bitmap.close();
  }
}

sourceFile.addEventListener("change", async () => {
  clearResult();
  source = undefined;
  const file = sourceFile.files?.[0];
  if (!file) {
    setStatus("Choose a PNG or JPEG to begin.");
    updateControls();
    return;
  }
  setStatus("Decoding image…");
  updateControls();
  try {
    await decodeSource(file);
    setStatus("Image ready. Choose an output size and resize.");
  } catch (error) {
    setStatus(error instanceof Error ? error.message : "Unable to decode this image.", true);
  }
  updateControls();
});

for (const input of [targetWidth, targetHeight]) {
  input.addEventListener("input", updateControls);
}

resizeButton.addEventListener("click", async () => {
  const message = validationMessage();
  if (message || !source) {
    setStatus(message ?? "Choose a PNG or JPEG image first.", true);
    updateControls();
    return;
  }
  const width = positiveInteger(targetWidth)!;
  const height = positiveInteger(targetHeight)!;
  isRunning = true;
  clearResult();
  setStatus("Resizing image…");
  updateControls();
  try {
    const response = await client.resize(source.pixels, source.width, source.height, width, height);
    if (response.type === "failure") throw new Error(response.message);
    const pixels = new Uint8ClampedArray(response.pixels);
    const expectedLength = response.width * response.height * 4;
    if (pixels.length !== expectedLength) throw new Error("WASM worker returned invalid pixel data.");
    resultCanvas.width = response.width;
    resultCanvas.height = response.height;
    resultContext.putImageData(new ImageData(pixels, response.width, response.height), 0, 0);
    result = { pixels, width: response.width, height: response.height };
    resultDimensions.textContent = `${response.width} × ${response.height}`;
    setStatus("Resize complete. Download the PNG when ready.");
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      setStatus("Resize cancelled.");
    } else {
      setStatus(error instanceof Error ? `Resize failed: ${error.message}` : "Resize failed.", true);
    }
  } finally {
    isRunning = false;
    updateControls();
  }
});

cancelButton.addEventListener("click", () => {
  if (!isRunning) return;
  client.cancel();
  // The client rejects the pending promise synchronously; keep the UI disabled
  // until its resize handler observes that rejection and installs the new worker.
  setStatus("Cancelling resize…");
});

downloadButton.addEventListener("click", async () => {
  if (!result) return;
  const blob = await new Promise<Blob | null>((resolve) => resultCanvas.toBlob(resolve, "image/png"));
  if (!blob) {
    setStatus("Unable to create a PNG download.", true);
    return;
  }
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "seamcarved.png";
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
});

updateControls();
