import type { ResizeRequestMessage, ResizeSuccessMessage } from "./protocol.js";
import type { WasmCPUProcessor as WasmCPUProcessorContract } from "./selector.js";

export type WasmResizeCallable = (request: ResizeRequestMessage) => Promise<ResizeSuccessMessage>;

/** Thin adapter around the Swift global installed by the generated WASM runtime. */
export class WasmCPUProcessor implements WasmCPUProcessorContract {
  constructor(private readonly wasmResize: WasmResizeCallable) {}

  resize(request: ResizeRequestMessage): Promise<ResizeSuccessMessage> {
    return this.wasmResize(request);
  }
}
