import { describe, expect, it, vi } from "vitest";
import type { ResizeRequestMessage, ResizeSuccessMessage } from "../src/protocol.js";
import {
  isWebGPUEligible,
  ResizeSelector,
  type GPUProcessor,
  type WasmCPUProcessor,
} from "../src/selector.js";
import { WebGPUProcessor } from "../src/webgpu.js";

function request(
  sourceWidth: number,
  sourceHeight: number,
  targetWidth: number,
  targetHeight: number,
): ResizeRequestMessage {
  return {
    type: "resize",
    jobId: 1,
    pixels: new ArrayBuffer(sourceWidth * sourceHeight * 4),
    sourceWidth,
    sourceHeight,
    targetWidth,
    targetHeight,
  };
}

function success(request: ResizeRequestMessage, backend: "wasm-cpu" | "webgpu" = "wasm-cpu"): ResizeSuccessMessage {
  return {
    type: "success",
    backend,
    jobId: request.jobId,
    pixels: new ArrayBuffer(request.targetWidth * request.targetHeight * 4),
    width: request.targetWidth,
    height: request.targetHeight,
  };
}

function cpu(): WasmCPUProcessor {
  return { resize: vi.fn(async (value: ResizeRequestMessage) => success(value)) };
}

describe("isWebGPUEligible", () => {
  it("accepts exactly vertical shrink requests", () => {
    expect(isWebGPUEligible(request(8, 4, 7, 4))).toBe(true);
    expect(isWebGPUEligible(request(8, 4, 8, 3))).toBe(false);
    expect(isWebGPUEligible(request(8, 4, 9, 4))).toBe(false);
    expect(isWebGPUEligible(request(8, 4, 8, 4))).toBe(false);
    expect(isWebGPUEligible(request(8, 4, 0, 4))).toBe(false);
  });
});

describe("ResizeSelector", () => {
  it("does not initialize WebGPU for an ineligible request", async () => {
    const wasm = cpu();
    const gpu: GPUProcessor = {
      initialize: vi.fn(async () => {}),
      resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
    };
    const selector = new ResizeSelector(wasm, () => gpu, () => ({ gpu: {} }));
    const value = request(8, 4, 8, 3);

    await expect(selector.resize(value)).resolves.toMatchObject({ backend: "wasm-cpu" });
    expect(gpu.initialize).not.toHaveBeenCalled();
    expect(gpu.resize).not.toHaveBeenCalled();
    expect(wasm.resize).toHaveBeenCalledOnce();
  });

  it("falls back exactly once when eligible GPU initialization fails", async () => {
    const wasm = cpu();
    const gpu: GPUProcessor = {
      initialize: vi.fn(async () => { throw new Error("WebGPU unavailable"); }),
      resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
    };
    const selector = new ResizeSelector(wasm, () => gpu, () => ({ gpu: {} }));
    const value = request(8, 4, 7, 4);

    await expect(selector.resize(value)).resolves.toMatchObject({ backend: "wasm-cpu" });
    expect(gpu.initialize).toHaveBeenCalledOnce();
    expect(gpu.resize).not.toHaveBeenCalled();
    expect(wasm.resize).toHaveBeenCalledTimes(1);
    expect(wasm.resize).toHaveBeenCalledWith(value);
  });

  it("routes once to CPU when the device is lost before GPU submission completes", async () => {
    let resolveLost!: () => void;
    const lost = new Promise<void>((resolve) => { resolveLost = resolve; });
    const wasm = cpu();
    const gpu: GPUProcessor = {
      initialize: vi.fn(async () => {}),
      device: { lost },
      resize: vi.fn(async () => {
        resolveLost();
        throw new Error("device lost before submit");
      }),
    };
    const selector = new ResizeSelector(wasm, () => gpu, () => ({ gpu: {} }));
    const value = request(8, 4, 7, 4);

    await expect(selector.resize(value)).resolves.toMatchObject({ backend: "wasm-cpu" });
    expect(gpu.resize).toHaveBeenCalledOnce();
    expect(wasm.resize).toHaveBeenCalledTimes(1);
    expect(wasm.resize).toHaveBeenCalledWith(value);
  });

  it("falls back to WASM when asynchronous WebGPU pipeline validation rejects", async () => {
    vi.stubGlobal("GPUBufferUsage", {
      MAP_READ: 1,
      COPY_SRC: 2,
      COPY_DST: 4,
      STORAGE: 8,
      UNIFORM: 16,
    });
    try {
      const pipelineFailure = vi.fn(async () => { throw new Error("WGSL validation failed"); });
      const buffer = {
        mapAsync: vi.fn(async () => {}),
        getMappedRange: vi.fn(() => new ArrayBuffer(0)),
        unmap: vi.fn(),
        destroy: vi.fn(),
      };
      const processor = new WebGPUProcessor();
      processor.device = {
        queue: { writeBuffer: vi.fn(), submit: vi.fn() },
        lost: new Promise(() => {}),
        createBuffer: vi.fn(() => buffer),
        createShaderModule: vi.fn(() => ({})),
        createComputePipelineAsync: pipelineFailure,
        createBindGroup: vi.fn(),
        createCommandEncoder: vi.fn(),
      } as never;
      const wasm = cpu();
      const gpu: GPUProcessor = {
        initialize: vi.fn(async () => {}),
        resize: (value) => processor.resize(value),
      };
      const value = request(3, 3, 2, 3);
      const selector = new ResizeSelector(wasm, () => gpu, () => ({ gpu: {} }));

      await expect(selector.resize(value)).resolves.toMatchObject({ backend: "wasm-cpu" });
      expect(pipelineFailure).toHaveBeenCalledOnce();
      expect(wasm.resize).toHaveBeenCalledOnce();
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

describe("ResizeSelector GPU lifecycle", () => {
  it("uses CPU when WebGPU is unavailable without creating a processor", async () => {
    const wasm = cpu();
    const createGPUProcessor = vi.fn((): GPUProcessor => ({
      initialize: vi.fn(async () => {}),
      resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
    }));
    const selector = new ResizeSelector(wasm, createGPUProcessor, () => undefined);

    await expect(selector.resize(request(8, 4, 7, 4))).resolves.toMatchObject({ backend: "wasm-cpu" });
    expect(createGPUProcessor).not.toHaveBeenCalled();
    expect(wasm.resize).toHaveBeenCalledOnce();
  });

  it("clears a lost device so a later eligible request initializes a fresh processor", async () => {
    let resolveLost!: () => void;
    const lost = new Promise<void>((resolve) => { resolveLost = resolve; });
    const first: GPUProcessor = {
      initialize: vi.fn(async () => {}),
      resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
      device: { lost },
    };
    const second: GPUProcessor = {
      initialize: vi.fn(async () => {}),
      resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
    };
    const createGPUProcessor = vi.fn()
      .mockReturnValueOnce(first)
      .mockReturnValueOnce(second);
    const wasm = cpu();
    const selector = new ResizeSelector(wasm, createGPUProcessor, () => ({ gpu: {} }));
    const value = request(8, 4, 7, 4);

    await expect(selector.resize(value)).resolves.toMatchObject({ backend: "webgpu" });
    resolveLost();
    await Promise.resolve();
    await expect(selector.resize({ ...value, jobId: 2 })).resolves.toMatchObject({ backend: "webgpu" });

    expect(createGPUProcessor).toHaveBeenCalledTimes(2);
    expect(first.initialize).toHaveBeenCalledOnce();
    expect(second.initialize).toHaveBeenCalledOnce();
  });
});

describe("WebGPU multi-seam encoding", () => {
  it("keeps multi-seam intermediates on the device and maps only the final target", async () => {
    vi.stubGlobal("GPUBufferUsage", {
      MAP_READ: 1,
      COPY_SRC: 2,
      COPY_DST: 4,
      STORAGE: 8,
      UNIFORM: 16,
    });
    vi.stubGlobal("GPUMapMode", { READ: 1 });
    try {
      const buffers: Array<{ size: number; mapAsync: ReturnType<typeof vi.fn>; getMappedRange: ReturnType<typeof vi.fn>; unmap: ReturnType<typeof vi.fn>; destroy: ReturnType<typeof vi.fn> }> = [];
      const pass = { setPipeline: vi.fn(), setBindGroup: vi.fn(), dispatchWorkgroups: vi.fn(), end: vi.fn() };
      const encoder = {
        beginComputePass: vi.fn(() => pass),
        copyBufferToBuffer: vi.fn(),
        finish: vi.fn(() => ({})),
      };
      const pipeline = { getBindGroupLayout: vi.fn(() => ({})) };
      const processor = new WebGPUProcessor();
      processor.device = {
        queue: { writeBuffer: vi.fn(), submit: vi.fn() },
        lost: new Promise(() => {}),
        createBuffer: vi.fn(({ size }: { size: number }) => {
          const buffer = {
            size,
            mapAsync: vi.fn(async () => {}),
            getMappedRange: vi.fn(() => new ArrayBuffer(size)),
            unmap: vi.fn(),
            destroy: vi.fn(),
          };
          buffers.push(buffer);
          return buffer;
        }),
        createShaderModule: vi.fn(() => ({})),
        createComputePipelineAsync: vi.fn(async () => pipeline),
        pushErrorScope: vi.fn(),
        popErrorScope: vi.fn(async () => null),
        createBindGroup: vi.fn(() => ({})),
        createCommandEncoder: vi.fn(() => encoder),
      } as never;

      const value = request(4, 2, 2, 2);
      await expect(processor.resize(value)).resolves.toMatchObject({
        backend: "webgpu",
        width: 2,
        height: 2,
      });

      expect(processor.device.queue.submit).toHaveBeenCalledOnce();
      expect(pass.dispatchWorkgroups).toHaveBeenCalledTimes(14);
      expect(encoder.copyBufferToBuffer).toHaveBeenCalledOnce();
      expect(buffers.filter((buffer) => buffer.mapAsync.mock.calls.length > 0)).toHaveLength(1);
      expect(buffers.flatMap((buffer) => buffer.mapAsync.mock.calls)).toHaveLength(1);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

describe("ResizeSelector concrete WebGPU device loss", () => {
  it("uses CPU without a WebGPU success when device loss interrupts final mapping, then reinitializes", async () => {
    vi.stubGlobal("GPUBufferUsage", {
      MAP_READ: 1,
      COPY_SRC: 2,
      COPY_DST: 4,
      STORAGE: 8,
      UNIFORM: 16,
    });
    vi.stubGlobal("GPUMapMode", { READ: 1 });
    try {
      let resolveLost!: () => void;
      const lost = new Promise<void>((resolve) => { resolveLost = resolve; });
      const pass = { setPipeline: vi.fn(), setBindGroup: vi.fn(), dispatchWorkgroups: vi.fn(), end: vi.fn() };
      const encoder = {
        beginComputePass: vi.fn(() => pass),
        copyBufferToBuffer: vi.fn(),
        finish: vi.fn(() => ({})),
      };
      const pipeline = { getBindGroupLayout: vi.fn(() => ({})) };
      const first = new WebGPUProcessor();
      first.device = {
        queue: { writeBuffer: vi.fn(), submit: vi.fn() },
        lost,
        createBuffer: vi.fn(({ size, usage }: { size: number; usage: number }) => ({
          mapAsync: usage & 1
            ? vi.fn(() => {
              resolveLost();
              return new Promise<void>(() => {});
            })
            : vi.fn(async () => {}),
          getMappedRange: vi.fn(() => new ArrayBuffer(size)),
          unmap: vi.fn(),
          destroy: vi.fn(),
        })),
        createShaderModule: vi.fn(() => ({})),
        createComputePipelineAsync: vi.fn(async () => pipeline),
        pushErrorScope: vi.fn(),
        popErrorScope: vi.fn(async () => null),
        createBindGroup: vi.fn(() => ({})),
        createCommandEncoder: vi.fn(() => encoder),
      } as never;
      const second: GPUProcessor = {
        initialize: vi.fn(async () => {}),
        resize: vi.fn(async (value: ResizeRequestMessage) => success(value, "webgpu")),
      };
      const createGPUProcessor = vi.fn()
        .mockReturnValueOnce(first)
        .mockReturnValueOnce(second);
      const wasm = cpu();
      const selector = new ResizeSelector(wasm, createGPUProcessor, () => ({ gpu: {} }));
      const value = request(3, 2, 2, 2);

      await expect(Promise.race([
        selector.resize(value),
        new Promise<never>((_, reject) => setTimeout(() => reject(new Error("device loss did not stop WebGPU mapping")), 100)),
      ])).resolves.toMatchObject({ backend: "wasm-cpu" });
      expect(wasm.resize).toHaveBeenCalledTimes(1);
      expect(wasm.resize).toHaveBeenCalledWith(value);

      await expect(selector.resize({ ...value, jobId: 2 })).resolves.toMatchObject({ backend: "webgpu" });
      expect(createGPUProcessor).toHaveBeenCalledTimes(2);
      expect(second.initialize).toHaveBeenCalledOnce();
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
