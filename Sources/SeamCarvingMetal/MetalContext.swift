import Foundation
@preconcurrency import Metal
@_spi(Backend) import SeamCarvingCore

public actor MetalContext {
    public nonisolated let device: any MTLDevice
    private let library: any MTLLibrary
    private let queue: any MTLCommandQueue
    private var pipelineCache: [String: any MTLComputePipelineState] = [:]

    public static func makeDefault() throws -> MetalContext {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SeamCarvingError.metalUnavailable
        }
        return try MetalContext(device: device)
    }

    public init(device: any MTLDevice) throws {
        self.device = device
        do {
            self.library = try MetalShaderLibrary.makeLibrary(on: device)
        } catch {
            throw error
        }
        guard let queue = device.makeCommandQueue() else {
            throw SeamCarvingError.metalExecutionFailed("command queue unavailable")
        }
        self.queue = queue
    }

    public func pipeline(named name: String) throws -> any MTLComputePipelineState {
        if let cached = pipelineCache[name] {
            return cached
        }
        guard let function = library.makeFunction(name: name) else {
            throw SeamCarvingError.metalExecutionFailed("missing kernel \(name)")
        }
        let pipeline: any MTLComputePipelineState
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw SeamCarvingError.metalExecutionFailed("pipeline \(name) failed: \(error)")
        }
        pipelineCache[name] = pipeline
        return pipeline
    }

    public func submit(_ encode: @Sendable (any MTLCommandBuffer) throws -> Void) async throws {
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw SeamCarvingError.metalExecutionFailed("command buffer unavailable")
        }
        do {
            try encode(commandBuffer)
        } catch {
            throw error
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: SeamCarvingError.metalExecutionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
            commandBuffer.commit()
        }
    }
}
