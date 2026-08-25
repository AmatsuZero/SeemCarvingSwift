import { describe, expect, it, vi } from "vitest";
import type { ResizeRequestMessage, ResizeSuccessMessage } from "../src/protocol.js";
import {
  isWebGPUEligible,
  ResizeSelector,
  type GPUProcessor,
  type WasmCPUProcessor,
} from "../src/selector.js";

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

  it("falls back exactly once when an initialized GPU fails before producing a result", async () => {
    const wasm = cpu();
    const gpu: GPUProcessor = {
      initialize: vi.fn(async () => {}),
      resize: vi.fn(async () => { throw new Error("mapAsync failed"); }),
    };
    const selector = new ResizeSelector(wasm, () => gpu, () => ({ gpu: {} }));
    const value = request(8, 4, 7, 4);

    await expect(selector.resize(value)).resolves.toMatchObject({ backend: "wasm-cpu" });
    expect(gpu.resize).toHaveBeenCalledOnce();
    expect(wasm.resize).toHaveBeenCalledTimes(1);
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
