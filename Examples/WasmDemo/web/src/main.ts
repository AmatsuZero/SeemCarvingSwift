import "./styles.css";
import { createSeamCarver, type ResizeResult, type SeamCarver } from "@seemcarving/wasm";

const workerStatus = document.querySelector<HTMLOutputElement>("[data-testid=worker-status]");
if (!workerStatus) throw new Error("Missing worker status output");

let client: SeamCarver | undefined;
let clientPromise = createClient();

function createClient(): Promise<SeamCarver> {
  workerStatus.textContent = "loading";
  const promise = createSeamCarver();
  void promise.then(
    (carver) => {
      client = carver;
      workerStatus.textContent = "ready";
    },
    () => { workerStatus.textContent = "error"; },
  );
  return promise;
}

function replaceClient(): void {
  client?.terminate();
  client = undefined;
  clientPromise = createClient();
}

declare global {
  interface Window {
    __testResizeRGBA8?: (
      pixels: Uint8Array, sourceWidth: number, sourceHeight: number, targetWidth: number, targetHeight: number,
    ) => Promise<ResizeResult>;
    __testTerminateActiveWorker?: () => void;
  }
}

if (import.meta.env.MODE === "test") {
  window.__testResizeRGBA8 = async (pixels, sourceWidth, sourceHeight, targetWidth, targetHeight) =>
    (await clientPromise).resize({
      pixels,
      width: sourceWidth,
      height: sourceHeight,
      targetWidth,
      targetHeight,
    });
  window.__testTerminateActiveWorker = () => replaceClient();
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

function updateControls(reportInvalid = false): void {
  const message = validationMessage();
  const valid = message === undefined;
  resizeButton.disabled = isRunning || !valid;
  cancelButton.disabled = !isRunning;
  downloadButton.disabled = isRunning || !result;
  sourceFile.disabled = isRunning;
  targetWidth.disabled = isRunning;
  targetHeight.disabled = isRunning;
  if (reportInvalid && source && message) setStatus(message, true);
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
    console.error("Image decode failed", error);
    setStatus(error instanceof Error ? error.message : "Unable to decode this image.", true);
  }
  updateControls();
});

for (const input of [targetWidth, targetHeight]) {
  input.addEventListener("input", () => updateControls(true));
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
    const response = await (await clientPromise).resize({
      pixels: source.pixels,
      width: source.width,
      height: source.height,
      targetWidth: width,
      targetHeight: height,
    });
    const pixels = new Uint8ClampedArray(response.pixels);
    const expectedLength = response.width * response.height * 4;
    if (pixels.length !== expectedLength) throw new Error("WASM worker returned invalid pixel data.");
    resultCanvas.width = response.width;
    resultCanvas.height = response.height;
    resultContext.putImageData(new ImageData(pixels, response.width, response.height), 0, 0);
    result = { pixels, width: response.width, height: response.height };
    resultDimensions.textContent = `${response.width} × ${response.height}`;
    setStatus(`Resize complete with ${response.backend}. Download the PNG when ready.`);
  } catch (error) {
    if (error instanceof Error && error.message.includes("terminated")) {
      setStatus("Resize cancelled.");
    } else {
      console.error("WASM resize failed", error);
      setStatus(error instanceof Error ? `Resize failed: ${error.message}` : "Resize failed.", true);
    }
  } finally {
    isRunning = false;
    updateControls();
  }
});

cancelButton.addEventListener("click", () => {
  if (!isRunning) return;
  replaceClient();
  // Keep the UI disabled until the terminated request settles in its resize handler.
  updateControls();
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
