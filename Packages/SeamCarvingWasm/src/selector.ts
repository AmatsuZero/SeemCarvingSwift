import type {
  ResizeProcessor,
  ResizeRequestMessage,
  ResizeSuccessMessage,
} from "./protocol.js";
import { WebGPUProcessor } from "./webgpu.js";

/** The CPU fallback contract used by the worker-owned selector. */
export interface WasmCPUProcessor extends ResizeProcessor {}

/**
 * The narrow GPU contract needed before the concrete WebGPU implementation lands.
 * A processor exposes device loss without leaking WebGPU DOM types into the
 * package protocol, so tests and non-WebGPU environments remain portable.
 */
export interface GPUProcessor extends ResizeProcessor {
  initialize(): Promise<void>;
  device?: { lost: Promise<unknown> };
}

export type GPUProcessorFactory = () => GPUProcessor | undefined;
type NavigatorHost = { gpu?: unknown };
type NavigatorGetter = () => NavigatorHost | undefined;

/** Resource bounds shared with the Swift/WASM bridge contract. */
export const PIXEL_LIMIT = 2_000_000;
export const ESTIMATED_WORK_LIMIT = 80_000_000;

function isSafePositiveInteger(value: number): boolean {
  return Number.isSafeInteger(value) && value > 0;
}

/**
 * Mirrors WasmBridgeCore's resource validation before a request can be sent to
 * WebGPU. The CPU bridge remains the authority for its own error reporting;
 * this guard prevents a GPU-eligible shape from bypassing that public limit.
 */
export function isWithinResourceLimits(request: ResizeRequestMessage): boolean {
  const {
    sourceWidth,
    sourceHeight,
    targetWidth,
    targetHeight,
  } = request;
  if (![sourceWidth, sourceHeight, targetWidth, targetHeight].every(isSafePositiveInteger)) {
    return false;
  }

  const sourcePixels = sourceWidth * sourceHeight;
  const targetPixels = targetWidth * targetHeight;
  if (!Number.isSafeInteger(sourcePixels) || !Number.isSafeInteger(targetPixels) ||
      sourcePixels > PIXEL_LIMIT || targetPixels > PIXEL_LIMIT) {
    return false;
  }

  const widthWork = Math.abs(sourceWidth - targetWidth) * sourceHeight;
  const heightWork = Math.abs(sourceHeight - targetHeight) * targetWidth;
  const estimatedWork = widthWork + heightWork;
  return Number.isSafeInteger(widthWork) &&
    Number.isSafeInteger(heightWork) &&
    Number.isSafeInteger(estimatedWork) &&
    estimatedWork <= ESTIMATED_WORK_LIMIT;
}

/** MVP support is only a positive-width vertical shrink with unchanged height. */
export function isWebGPUEligible(request: ResizeRequestMessage): boolean {
  return isWithinResourceLimits(request) &&
    request.targetWidth > 0 &&
    request.targetHeight === request.sourceHeight &&
    request.targetWidth < request.sourceWidth;
}

function browserNavigator(): NavigatorHost | undefined {
  return typeof navigator === "undefined" ? undefined : navigator as NavigatorHost;
}

/**
 * Selects WebGPU only when it can complete a supported request. Every GPU
 * setup or execution failure is deliberately hidden from the Worker boundary
 * by retrying that exact request through the WASM CPU processor once.
 */
export class ResizeSelector implements ResizeProcessor {
  private gpuProcessor: GPUProcessor | undefined;
  private initializing: Promise<GPUProcessor | undefined> | undefined;

  constructor(
    private readonly wasm: WasmCPUProcessor,
    private readonly createGPUProcessor: GPUProcessorFactory = () => new WebGPUProcessor(),
    private readonly getNavigator: NavigatorGetter = browserNavigator,
  ) {}

  async resize(request: ResizeRequestMessage): Promise<ResizeSuccessMessage> {
    if (!isWebGPUEligible(request)) return this.wasm.resize(request);

    const gpu = await this.getGPUProcessor();
    if (!gpu) return this.wasm.resize(request);

    try {
      return await gpu.resize(request);
    } catch {
      // A GPU exception has no public result. Drop it and make one CPU attempt
      // for the same request; worker.ts alone decides how CPU errors are posted.
      if (this.gpuProcessor === gpu) this.gpuProcessor = undefined;
      return this.wasm.resize(request);
    }
  }

  private async getGPUProcessor(): Promise<GPUProcessor | undefined> {
    if (this.gpuProcessor) return this.gpuProcessor;
    if (this.initializing) return this.initializing;

    // This is intentionally the first feature probe, after eligibility.
    if (!this.getNavigator()?.gpu) return undefined;

    this.initializing = this.initializeGPUProcessor();
    try {
      return await this.initializing;
    } finally {
      this.initializing = undefined;
    }
  }

  private async initializeGPUProcessor(): Promise<GPUProcessor | undefined> {
    try {
      const processor = this.createGPUProcessor();
      if (!processor) return undefined;
      await processor.initialize();
      this.gpuProcessor = processor;
      this.clearProcessorOnDeviceLoss(processor);
      return processor;
    } catch {
      return undefined;
    }
  }

  private clearProcessorOnDeviceLoss(processor: GPUProcessor): void {
    void processor.device?.lost.then(() => {
      if (this.gpuProcessor === processor) this.gpuProcessor = undefined;
    });
  }
}
