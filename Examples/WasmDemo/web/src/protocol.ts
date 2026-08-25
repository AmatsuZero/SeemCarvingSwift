/** Messages sent from the page to the isolated Swift/WASM worker. */
export interface ResizeRequestMessage {
  type: "resize";
  jobId: number;
  pixels: ArrayBuffer;
  sourceWidth: number;
  sourceHeight: number;
  targetWidth: number;
  targetHeight: number;
}

export interface WorkerReadyMessage {
  type: "ready";
  jobId: number;
}

export type BackendIdentifier = "wasm-cpu" | "webgpu";

export interface ResizeSuccessMessage {
  type: "success";
  backend: BackendIdentifier;
  jobId: number;
  pixels: ArrayBuffer;
  width: number;
  height: number;
}

export interface ResizeFailureMessage {
  type: "failure";
  jobId: number;
  message: string;
}

export type WorkerRequestMessage = ResizeRequestMessage;
export type ResizeResponseMessage = ResizeSuccessMessage;
export type WorkerResponseMessage =
  | WorkerReadyMessage
  | ResizeSuccessMessage
  | ResizeFailureMessage;
