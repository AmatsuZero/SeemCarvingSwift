import { describe, expect, it, vi } from "vitest";
import { createSeamCarver, createWorker, type ResizeRequest } from "../src/index.js";
import type { WorkerResponseMessage } from "../src/protocol.js";

class FakeWorker {
  onmessage: ((event: MessageEvent<WorkerResponseMessage>) => void) | null = null;
  onerror: ((event: ErrorEvent) => void) | null = null;
  terminated = false;
  posted: Array<{ message: unknown; transfer: Transferable[] | undefined }> = [];
  respondToResize = true;

  postMessage(message: unknown, transfer?: Transferable[]): void {
    this.posted.push({ message, transfer });
    const request = message as { jobId: number };
    if (!this.respondToResize || request.jobId === undefined) return;
    queueMicrotask(() => {
      this.emit({
        type: "success",
        backend: "wasm-cpu",
        jobId: request.jobId,
        width: 1,
        height: 1,
        pixels: new Uint8Array([255, 0, 0, 255]).buffer,
      });
    });
  }

  emitReady(): void {
    this.emit({ type: "ready", ready: true });
  }

  emitLegacyReady(): void {
    this.onmessage?.({ data: { type: "ready", jobId: 0 } } as MessageEvent<WorkerResponseMessage>);
  }

  emitFailure(message: string, jobId = 0): void {
    this.emit({ type: "failure", jobId, message });
  }

  emitError(): void {
    this.onerror?.({} as ErrorEvent);
  }

  terminate(): void {
    this.terminated = true;
  }

  private emit(message: WorkerResponseMessage): void {
    this.onmessage?.({ data: message } as MessageEvent<WorkerResponseMessage>);
  }
}

const request: ResizeRequest = {
  pixels: new Uint8Array([255, 0, 0, 255, 0, 255, 0, 255]),
  width: 2,
  height: 1,
  targetWidth: 1,
  targetHeight: 1,
};

async function readyCarver(worker = new FakeWorker()) {
  const creation = createSeamCarver({ worker: worker as unknown as Worker });
  worker.emitReady();
  return { carver: await creation, worker };
}

describe("createSeamCarver", () => {
  it("creates its module Worker through the public package helper", () => {
    const created: unknown[][] = [];
    class PackageWorker {
      constructor(...arguments_: unknown[]) {
        created.push(arguments_);
      }
    }
    vi.stubGlobal("Worker", PackageWorker);

    try {
      expect(createWorker()).toBeInstanceOf(PackageWorker);
      expect(created).toHaveLength(1);
      expect(created[0]?.[0]).toBeInstanceOf(URL);
      expect((created[0]?.[0] as URL).pathname).toMatch(/worker\.js$/);
      expect(created[0]?.[1]).toEqual({ type: "module" });
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("uses a Worker factory override while retaining direct Worker injection", async () => {
    const factory = vi.fn(() => new FakeWorker());
    const creation = createSeamCarver({ workerFactory: factory });
    const worker = factory.mock.results[0]?.value;
    expect(worker).toBeInstanceOf(FakeWorker);
    (worker as FakeWorker).emitReady();

    await expect(creation).resolves.toBeDefined();
    expect(factory).toHaveBeenCalledOnce();
  });

  it("terminates and rejects initialization when its abort signal fires", async () => {
    const worker = new FakeWorker();
    const controller = new AbortController();
    const creation = createSeamCarver({
      workerFactory: () => worker as unknown as Worker,
      signal: controller.signal,
    });

    controller.abort();

    await expect(creation).rejects.toThrow("terminated");
    expect(worker.terminated).toBe(true);
  });

  it("does not expose a just-ready carver after initialization is aborted", async () => {
    const worker = new FakeWorker();
    const controller = new AbortController();
    const creation = createSeamCarver({
      worker: worker as unknown as Worker,
      signal: controller.signal,
    });

    worker.emitReady();
    controller.abort();

    await expect(creation).rejects.toThrow("terminated");
    expect(worker.terminated).toBe(true);
  });

  it("waits for the Worker handshake, transfers a copied buffer, and resolves the result", async () => {
    const { carver, worker } = await readyCarver();

    await expect(carver.resize(request)).resolves.toMatchObject({
      backend: "wasm-cpu",
      width: 1,
      height: 1,
    });

    expect(worker.posted).toHaveLength(1);
    const [{ message, transfer }] = worker.posted;
    expect(transfer).toHaveLength(1);
    expect((message as { pixels: ArrayBuffer }).pixels).not.toBe(request.pixels.buffer);
    expect(request.pixels.byteLength).toBe(8);
  });

  it("rejects initialization failure before exposing a carver", async () => {
    const worker = new FakeWorker();
    const creation = createSeamCarver({ worker: worker as unknown as Worker });
    worker.emitLegacyReady();
    worker.emitFailure("WASM CPU resize callable is unavailable");

    await expect(creation).rejects.toThrow("WASM CPU resize callable is unavailable");
    expect(worker.terminated).toBe(true);
  });

  it("terminalizes on Worker error and rejects active and later requests", async () => {
    const { carver, worker } = await readyCarver();
    worker.respondToResize = false;

    const active = carver.resize(request);
    worker.emitError();

    await expect(active).rejects.toThrow("WASM worker failed");
    await expect(carver.resize(request)).rejects.toThrow("WASM worker failed");
    expect(worker.terminated).toBe(true);
  });

  it("rejects concurrent and terminated requests deterministically", async () => {
    const { carver, worker } = await readyCarver();
    worker.respondToResize = false;

    const active = carver.resize(request);
    await expect(carver.resize(request)).rejects.toThrow("already in progress");

    carver.terminate();
    await expect(active).rejects.toThrow("terminated");
    await expect(carver.resize(request)).rejects.toThrow("terminated");
    expect(worker.terminated).toBe(true);
  });
});
