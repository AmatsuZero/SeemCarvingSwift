import { describe, expect, it } from "vitest";
import { createSeamCarver, type ResizeRequest } from "../src/index.js";
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
