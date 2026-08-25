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
  createComputePipeline(descriptor: unknown): unknown;
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
 * WebGPU implementation of exactly one backward-Sobel vertical seam removal.
 * It keeps every intermediate buffer on the device and maps only the final RGBA8
 * output buffer after the one command encoder has completed.
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
    if (request.targetHeight !== request.sourceHeight || request.targetWidth !== request.sourceWidth - 1) {
      throw new RangeError("WebGPU currently supports exactly one vertical seam removal");
    }

    const width = request.sourceWidth;
    const height = request.sourceHeight;
    const pixelCount = width * height;
    const outputBytes = (width - 1) * height * 4;
    const device = this.device;
    const storage = usage("STORAGE");
    const copyDestination = usage("COPY_DST");
    const buffers: GPUBufferLike[] = [];
    const makeBuffer = (size: number, flags: number): GPUBufferLike => {
      const buffer = device.createBuffer({ size, usage: flags });
      buffers.push(buffer);
      return buffer;
    };
    const parameters = (row: number): GPUBufferLike => {
      const buffer = makeBuffer(16, usage("UNIFORM") | copyDestination);
      device.queue.writeBuffer(buffer, 0, new Uint32Array([width, height, row, 0]).buffer);
      return buffer;
    };
    const pipeline = (code: string): unknown => device.createComputePipeline({
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
      const input = makeBuffer(request.pixels.byteLength, storage | copyDestination);
      const luma = makeBuffer(pixelCount * 4, storage);
      const energy = makeBuffer(pixelCount * 4, storage);
      const rowA = makeBuffer(width * 4, storage);
      const rowB = makeBuffer(width * 4, storage);
      const parents = makeBuffer(pixelCount * 4, storage);
      const argmin = makeBuffer(4, storage);
      const seam = makeBuffer(height * 4, storage);
      const output = makeBuffer(outputBytes, storage | usage("COPY_SRC"));
      const readback = makeBuffer(outputBytes, usage("MAP_READ") | copyDestination);
      device.queue.writeBuffer(input, 0, request.pixels);

      const lumaPipeline = pipeline(rgbaToLumaWGSL);
      const sobelPipeline = pipeline(sobelWGSL);
      const initializePipeline = pipeline(initializeDPWGSL);
      const accumulatePipeline = pipeline(accumulateDPWGSL);
      const reducePipeline = pipeline(reduceWGSL);
      const backtrackPipeline = pipeline(backtrackWGSL);
      const removePipeline = pipeline(removeVerticalWGSL);
      const encoder = device.createCommandEncoder();
      const baseParameters = parameters(0);
      encode(encoder, lumaPipeline, bindGroup(lumaPipeline, [input, luma, baseParameters]), dispatchCount(pixelCount));
      encode(encoder, sobelPipeline, bindGroup(sobelPipeline, [luma, energy, baseParameters]), dispatchCount(pixelCount));
      encode(encoder, initializePipeline, bindGroup(initializePipeline, [energy, rowA, baseParameters]), dispatchCount(width));

      let previous = rowA;
      let current = rowB;
      for (let y = 1; y < height; y++) {
        const rowParameters = parameters(y);
        encode(
          encoder,
          accumulatePipeline,
          bindGroup(accumulatePipeline, [previous, current, parents, energy, rowParameters]),
          dispatchCount(width),
        );
        [previous, current] = [current, previous];
      }
      encode(encoder, reducePipeline, bindGroup(reducePipeline, [previous, argmin, baseParameters]), 1);
      encode(encoder, backtrackPipeline, bindGroup(backtrackPipeline, [parents, seam, argmin, baseParameters]), 1);
      encode(encoder, removePipeline, bindGroup(removePipeline, [input, output, seam, baseParameters]), dispatchCount((width - 1) * height));
      encoder.copyBufferToBuffer(output, 0, readback, 0, outputBytes);
      device.queue.submit([encoder.finish()]);
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
