/** The implementation selected for a resize operation. */
export type BackendIdentifier = "wasm-cpu" | "webgpu";

/** Message sent from the SDK client to its isolated worker. */
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
export type WorkerResponseMessage =
  | WorkerReadyMessage
  | ResizeSuccessMessage
  | ResizeFailureMessage;
