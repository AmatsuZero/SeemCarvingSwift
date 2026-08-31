import Foundation
import SeamCarvingCore

public struct AndroidResizeResult {
    public let width: Int32
    public let height: Int32
    public let bytes: [UInt8]

    public init(width: Int32, height: Int32, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }
}

public enum AndroidResizeBridge {
    public static func resize(
        width: Int32,
        height: Int32,
        bytes: [UInt8],
        targetWidth: Int32,
        targetHeight: Int32,
        protectionMask: [Float],
        removalMask: [Float]
    ) async throws -> AndroidResizeResult {
        try await performResize(
            width: width,
            height: height,
            bytes: bytes,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            protectionMask: protectionMask,
            removalMask: removalMask,
            progress: nil
        )
    }

    fileprivate static func performResize(
        width: Int32,
        height: Int32,
        bytes: [UInt8],
        targetWidth: Int32,
        targetHeight: Int32,
        protectionMask: [Float],
        removalMask: [Float],
        progress: (@Sendable (SeamCarvingCore.ResizeProgress) -> Void)?
    ) async throws -> AndroidResizeResult {
        let source = try RGBA8Image(
            width: Int(width),
            height: Int(height),
            pixels: bytes
        )
        let target = try PixelSize(width: Int(targetWidth), height: Int(targetHeight))
        let masks = try MaskPair(
            protectionLayers: protectionMask.isEmpty ? [] : [
                try ProtectionLayer(
                    mask: Mask(width: source.width, height: source.height, values: protectionMask),
                    strength: .soft(1_000)
                ),
            ],
            removal: removalMask.isEmpty
                ? nil
                : try Mask(width: source.width, height: source.height, values: removalMask),
            removalWeight: 1_000
        )
        let result = try await SeamCarver().resize(
            source,
            to: target,
            options: ResizeOptions(masks: masks, progress: progress)
        )
        return AndroidResizeResult(
            width: try checkedDimension(result.width),
            height: try checkedDimension(result.height),
            bytes: result.pixels
        )
    }

    fileprivate static func checkedDimension(_ value: Int) throws -> Int32 {
        guard let dimension = Int32(exactly: value) else {
            throw SeamCarvingError.invalidDimensions
        }
        return dimension
    }
}

/// A single-use Android resize operation whose lifecycle can be cancelled from
/// the Kotlin coroutine that owns it.
public final class AndroidResizeOperation: @unchecked Sendable {
    private let state = AndroidResizeOperationState()

    public init() {}

    public func resize(
        width: Int32,
        height: Int32,
        bytes: [UInt8],
        targetWidth: Int32,
        targetHeight: Int32,
        protectionMask: [Float],
        removalMask: [Float],
        progress: @escaping @Sendable (
            Int32,
            Int32,
            Int32,
            Int32
        ) -> Bool
    ) async throws -> AndroidResizeResult {
        let operationTask = Task {
            try await AndroidResizeBridge.performResize(
                width: width,
                height: height,
                bytes: bytes,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                protectionMask: protectionMask,
                removalMask: removalMask,
                progress: { [state] update in
                    guard state.beginProgressDelivery() else { return }
                    let shouldContinue = progress(
                        Int32(update.completedEdits),
                        Int32(update.totalEdits),
                        Int32(update.size.width),
                        Int32(update.size.height)
                    )
                    state.endProgressDelivery()
                    if !shouldContinue {
                        state.cancelFromProgressCallback()
                    }
                }
            )
        }
        state.install(cancellationAction: {
            operationTask.cancel()
        })
        defer { state.finish() }

        return try await withTaskCancellationHandler {
            try await operationTask.value
        } onCancel: { [state] in
            state.cancelAndWaitForProgressDelivery()
        }
    }

    public func cancel() {
        state.cancelAndWaitForProgressDelivery()
    }
}

final class AndroidResizeOperationState: @unchecked Sendable {
    typealias CancellationAction = () -> Void

    private let condition = NSCondition()
    private var cancellationAction: CancellationAction?
    private var cancellationRequested = false
    private var activeProgressDeliveries = 0

    func install(cancellationAction: @escaping CancellationAction) {
        condition.lock()
        self.cancellationAction = cancellationAction
        let shouldCancel = cancellationRequested
        if shouldCancel {
            self.cancellationAction = nil
        }
        condition.unlock()
        if shouldCancel {
            cancellationAction()
        }
    }

    func finish() {
        condition.lock()
        cancellationAction = nil
        condition.unlock()
    }

    func beginProgressDelivery() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !cancellationRequested else { return false }
        activeProgressDeliveries += 1
        return true
    }

    func endProgressDelivery() {
        condition.lock()
        activeProgressDeliveries -= 1
        if activeProgressDeliveries == 0 {
            condition.broadcast()
        }
        condition.unlock()
    }

    func cancelFromProgressCallback() {
        markCancelled()?()
    }

    func cancelAndWaitForProgressDelivery() {
        markCancelled()?()

        condition.lock()
        while activeProgressDeliveries > 0 {
            condition.wait()
        }
        condition.unlock()
    }

    private func markCancelled() -> CancellationAction? {
        condition.lock()
        guard !cancellationRequested else {
            condition.unlock()
            return nil
        }
        cancellationRequested = true
        let cancellationAction = cancellationAction
        self.cancellationAction = nil
        condition.unlock()
        return cancellationAction
    }
}
