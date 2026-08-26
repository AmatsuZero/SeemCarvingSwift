import type { ResizeRequestMessage, ResizeSuccessMessage } from "./protocol.js";
import {
  accumulateDPWGSL,
  backtrackWGSL,
  initializeDPWGSL,
  reduceWGSL,
  removeVerticalWGSL,
  rgbaToLumaWGSL,
  sobelWGSL,
} from "./shaders.js";

type GPUBufferLike = {
  mapAsync(mode: number): Promise<void>;
  getMappedRange(): ArrayBuffer;
  unmap(): void;
  destroy(): void;
};
type GPUDeviceLike = {
  queue: { writeBuffer(buffer: GPUBufferLike, offset: number, data: ArrayBuffer): void; submit(commands: unknown[]): void };
  lost: Promise<unknown>;
  createBuffer(descriptor: { size: number; usage: number }): GPUBufferLike;
  createShaderModule(descriptor: { code: string }): unknown;
  createComputePipelineAsync(descriptor: unknown): Promise<unknown>;
  pushErrorScope(filter: "validation"): void;
  popErrorScope(): Promise<unknown | null>;
  createBindGroup(descriptor: unknown): unknown;
  createCommandEncoder(): {
    beginComputePass(): { setPipeline(value: unknown): void; setBindGroup(index: number, value: unknown): void; dispatchWorkgroups(x: number): void; end(): void };
    copyBufferToBuffer(source: GPUBufferLike, sourceOffset: number, destination: GPUBufferLike, destinationOffset: number, size: number): void;
    finish(): unknown;
  };
};
type GPUAdapterLike = { requestDevice(): Promise<GPUDeviceLike> };
type GPUHost = { gpu?: { requestAdapter(): Promise<GPUAdapterLike | null> } };

const workgroupSize = 64;
const usage = (name: "MAP_READ" | "COPY_SRC" | "COPY_DST" | "STORAGE" | "UNIFORM"): number => {
  const value = (globalThis as unknown as { GPUBufferUsage?: Record<string, number> }).GPUBufferUsage?.[name];
  if (typeof value !== "number") throw new Error("WebGPU buffer usage constants are unavailable");
  return value;
};

const mapRead = (): number => {
  const value = (globalThis as unknown as { GPUMapMode?: { READ?: number } }).GPUMapMode?.READ;
  if (typeof value !== "number") throw new Error("WebGPU map mode constants are unavailable");
  return value;
};

function dispatchCount(items: number): number {
  return Math.ceil(items / workgroupSize);
}

/**
 * WebGPU implementation of backward-Sobel vertical shrink. It keeps every
 * intermediate seam buffer on the device and maps only the final RGBA8 output.
 */
export class WebGPUProcessor {
  device: GPUDeviceLike | undefined;

  static async initialize(): Promise<WebGPUProcessor> {
    const processor = new WebGPUProcessor();
    await processor.initialize();
    return processor;
  }

  async initialize(): Promise<void> {
    if (this.device) return;
    const host = globalThis as unknown as { navigator?: GPUHost };
    const adapter = await host.navigator?.gpu?.requestAdapter();
    if (!adapter) throw new Error("WebGPU adapter is unavailable");
    this.device = await adapter.requestDevice();
  }

  async resize(request: ResizeRequestMessage): Promise<ResizeSuccessMessage> {
    if (!this.device) throw new Error("WebGPU processor has not initialized");
    if (request.targetHeight !== request.sourceHeight || request.targetWidth <= 0 || request.targetWidth >= request.sourceWidth) {
      throw new RangeError("WebGPU supports only positive-width vertical shrink requests");
    }

    const sourceWidth = request.sourceWidth;
    const height = request.sourceHeight;
    const sourcePixelCount = sourceWidth * height;
    const sourceBytes = sourcePixelCount * 4;
    const targetBytes = request.targetWidth * height * 4;
    const device = this.device;
    const storage = usage("STORAGE");
    const copyDestination = usage("COPY_DST");
    const buffers: GPUBufferLike[] = [];
    const makeBuffer = (size: number, flags: number): GPUBufferLike => {
      const buffer = device.createBuffer({ size, usage: flags });
      buffers.push(buffer);
      return buffer;
    };
    const parameters = (width: number, row: number): GPUBufferLike => {
      const buffer = makeBuffer(16, usage("UNIFORM") | copyDestination);
      device.queue.writeBuffer(buffer, 0, new Uint32Array([width, height, row, 0]).buffer);
      return buffer;
    };
    const pipeline = async (code: string): Promise<unknown> => device.createComputePipelineAsync({
      layout: "auto",
      compute: { module: device.createShaderModule({ code }), entryPoint: "main" },
    });
    const bindGroup = (computePipeline: unknown, entries: GPUBufferLike[]): unknown =>
      device.createBindGroup({
        layout: (computePipeline as { getBindGroupLayout(index: number): unknown }).getBindGroupLayout(0),
        entries: entries.map((buffer, binding) => ({ binding, resource: { buffer } })),
      });
    const encode = (encoder: ReturnType<GPUDeviceLike["createCommandEncoder"]>, computePipeline: unknown, group: unknown, groups: number): void => {
      const pass = encoder.beginComputePass();
      pass.setPipeline(computePipeline);
      pass.setBindGroup(0, group);
      pass.dispatchWorkgroups(groups);
      pass.end();
    };

    try {
      // Both images retain source capacity. Each removal writes a densely packed
      // current-width-minus-one image, then swaps roles without a CPU round trip.
      const imageA = makeBuffer(sourceBytes, storage | copyDestination | usage("COPY_SRC"));
      const imageB = makeBuffer(sourceBytes, storage | usage("COPY_SRC"));
      const luma = makeBuffer(sourcePixelCount * 4, storage);
      const energy = makeBuffer(sourcePixelCount * 4, storage);
      const rowA = makeBuffer(sourceWidth * 4, storage);
      const rowB = makeBuffer(sourceWidth * 4, storage);
      const parents = makeBuffer(sourcePixelCount * 4, storage);
      const argmin = makeBuffer(4, storage);
      const seam = makeBuffer(height * 4, storage);
      const readback = makeBuffer(targetBytes, usage("MAP_READ") | copyDestination);
      device.queue.writeBuffer(imageA, 0, request.pixels);

      const lumaPipeline = await pipeline(rgbaToLumaWGSL);
      const sobelPipeline = await pipeline(sobelWGSL);
      const initializePipeline = await pipeline(initializeDPWGSL);
      const accumulatePipeline = await pipeline(accumulateDPWGSL);
      const reducePipeline = await pipeline(reduceWGSL);
      const backtrackPipeline = await pipeline(backtrackWGSL);
      const removePipeline = await pipeline(removeVerticalWGSL);

      let currentImage = imageA;
      let nextImage = imageB;
      const encoder = device.createCommandEncoder();
      device.pushErrorScope("validation");
      for (let currentWidth = sourceWidth; currentWidth > request.targetWidth; currentWidth--) {
        const baseParameters = parameters(currentWidth, 0);
        encode(encoder, lumaPipeline, bindGroup(lumaPipeline, [currentImage, luma, baseParameters]), dispatchCount(currentWidth * height));
        encode(encoder, sobelPipeline, bindGroup(sobelPipeline, [luma, energy, baseParameters]), dispatchCount(currentWidth * height));
        encode(encoder, initializePipeline, bindGroup(initializePipeline, [energy, rowA, baseParameters]), dispatchCount(currentWidth));

        let previous = rowA;
        let current = rowB;
        for (let y = 1; y < height; y++) {
          const rowParameters = parameters(currentWidth, y);
          encode(
            encoder,
            accumulatePipeline,
            bindGroup(accumulatePipeline, [previous, current, parents, energy, rowParameters]),
            dispatchCount(currentWidth),
          );
          [previous, current] = [current, previous];
        }
        encode(encoder, reducePipeline, bindGroup(reducePipeline, [previous, argmin, baseParameters]), 1);
        encode(encoder, backtrackPipeline, bindGroup(backtrackPipeline, [parents, seam, argmin, baseParameters]), 1);
        encode(encoder, removePipeline, bindGroup(removePipeline, [currentImage, nextImage, seam, baseParameters]), dispatchCount((currentWidth - 1) * height));
        [currentImage, nextImage] = [nextImage, currentImage];
      }
      encoder.copyBufferToBuffer(currentImage, 0, readback, 0, targetBytes);
      device.queue.submit([encoder.finish()]);
      const validationError = await device.popErrorScope();
      if (validationError) throw new Error(`WebGPU validation failed: ${String(validationError)}`);

      // Mapping happens once, after all seam passes and the final device copy.
      await readback.mapAsync(mapRead());
      const pixels = readback.getMappedRange().slice(0);
      readback.unmap();
      return {
        type: "success",
        backend: "webgpu",
        jobId: request.jobId,
        pixels,
        width: request.targetWidth,
        height: request.targetHeight,
      };
    } finally {
      for (const buffer of buffers) buffer.destroy();
    }
  }
}
