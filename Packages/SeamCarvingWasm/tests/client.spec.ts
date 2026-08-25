import { describe, expect, it } from "vitest";
import { createSeamCarver, type ResizeRequest } from "../src/index.js";
import type { WorkerResponseMessage } from "../src/protocol.js";

class FakeWorker {
  onmessage: ((event: MessageEvent<WorkerResponseMessage>) => void) | null = null;
  onerror: ((event: ErrorEvent) => void) | null = null;
  terminated = false;
  posted: Array<{ message: unknown; transfer: Transferable[] | undefined }> = [];

  postMessage(message: unknown, transfer?: Transferable[]): void {
    this.posted.push({ message, transfer });
    const request = message as { jobId: number };
    queueMicrotask(() => {
      this.onmessage?.({
        data: {
          type: "success",
          backend: "wasm-cpu",
          jobId: request.jobId,
          width: 1,
          height: 1,
          pixels: new Uint8Array([255, 0, 0, 255]).buffer,
        },
      } as MessageEvent<WorkerResponseMessage>);
    });
  }

  terminate(): void {
    this.terminated = true;
  }
}

const request: ResizeRequest = {
  pixels: new Uint8Array([255, 0, 0, 255, 0, 255, 0, 255]),
  width: 2,
  height: 1,
  targetWidth: 1,
  targetHeight: 1,
};

describe("createSeamCarver", () => {
  it("transfers a copied buffer and resolves the worker result", async () => {
    const worker = new FakeWorker();
    const carver = await createSeamCarver({ worker: worker as unknown as Worker });

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

  it("rejects concurrent and terminated requests deterministically", async () => {
    const worker = new FakeWorker();
    worker.postMessage = () => {};
    const carver = await createSeamCarver({ worker: worker as unknown as Worker });

    const active = carver.resize(request);
    await expect(carver.resize(request)).rejects.toThrow("already in progress");

    carver.terminate();
    await expect(active).rejects.toThrow("terminated");
    await expect(carver.resize(request)).rejects.toThrow("terminated");
    expect(worker.terminated).toBe(true);
  });
});
