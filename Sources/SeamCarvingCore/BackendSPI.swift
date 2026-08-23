@_spi(Backend)
public protocol SeamCarvingBackend: Sendable {
    var identifier: String { get }
    func findSeam(in image: RGBA8Image, orientation: SeamOrientation, options: ResizeOptions) async throws -> SeamPath
    func resize(_ image: RGBA8Image, to target: PixelSize, options: ResizeOptions) async throws -> RGBA8Image
}

@_spi(Backend)
public protocol BackwardEnergyProvider: Sendable {
    func compute(for image: RGBA8Image, blurRadius: Int, sobelThreshold: Float) throws -> EnergyMap
}

import Dispatch
import Foundation

@_spi(Benchmark)
public struct BackendPhaseDurations: Sendable, Codable, Equatable {
    public var bridgeNS: UInt64
    public var energyNS: UInt64
    public var maskNS: UInt64
    public var dynamicProgrammingNS: UInt64
    public var backtrackNS: UInt64
    public var editNS: UInt64
    public var commandEncodingNS: UInt64
    public var gpuWaitNS: UInt64
    public var totalNS: UInt64
    public var peakScratchBytes: UInt64

    public init(
        bridgeNS: UInt64,
        energyNS: UInt64,
        maskNS: UInt64,
        dynamicProgrammingNS: UInt64,
        backtrackNS: UInt64,
        editNS: UInt64,
        commandEncodingNS: UInt64,
        gpuWaitNS: UInt64,
        totalNS: UInt64,
        peakScratchBytes: UInt64
    ) {
        self.bridgeNS = bridgeNS
        self.energyNS = energyNS
        self.maskNS = maskNS
        self.dynamicProgrammingNS = dynamicProgrammingNS
        self.backtrackNS = backtrackNS
        self.editNS = editNS
        self.commandEncodingNS = commandEncodingNS
        self.gpuWaitNS = gpuWaitNS
        self.totalNS = totalNS
        self.peakScratchBytes = peakScratchBytes
    }
}

@_spi(Benchmark)
public final class BackendTimingRecorder: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private(set) var durations = BackendPhaseDurations(
        bridgeNS: 0, energyNS: 0, maskNS: 0, dynamicProgrammingNS: 0,
        backtrackNS: 0, editNS: 0, commandEncodingNS: 0, gpuWaitNS: 0,
        totalNS: 0, peakScratchBytes: 0
    )

    func add(_ phase: WritableKeyPath<BackendPhaseDurations, UInt64>, _ elapsed: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        durations[keyPath: phase] += elapsed
    }

    func measure<T>(_ phase: WritableKeyPath<BackendPhaseDurations, UInt64>, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { add(phase, DispatchTime.now().uptimeNanoseconds - start) }
        return try body()
    }

    public func snapshot() -> BackendPhaseDurations {
        lock.lock()
        defer { lock.unlock() }
        return durations
    }

    public func record(_ phase: WritableKeyPath<BackendPhaseDurations, UInt64>, elapsed: UInt64) {
        add(phase, elapsed)
    }

    public func recordScratch(bytes: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        durations.peakScratchBytes = max(durations.peakScratchBytes, bytes)
    }
}

@_spi(Benchmark)
public protocol InstrumentedSeamCarvingBackend: SeamCarvingBackend {
    func benchmarkResize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> (RGBA8Image, BackendPhaseDurations)
}

@_spi(Backend)
public struct MappedSeamSet: Sendable, Equatable {
    public let orientation: SeamOrientation
    public let coordinatesBySeam: [[UInt32]]

    public init(orientation: SeamOrientation, coordinatesBySeam: [[UInt32]]) throws {
        guard let first = coordinatesBySeam.first, !first.isEmpty else {
            throw SeamCarvingError.invalidConfiguration("empty mapped seam set")
        }
        for seam in coordinatesBySeam where seam.count != first.count {
            throw SeamCarvingError.invalidConfiguration("mapped seam length mismatch")
        }
        self.orientation = orientation
        self.coordinatesBySeam = coordinatesBySeam
    }
}

/// Shared orchestration for exact sequential seam carving. CPU and Accelerate
/// backends both reuse this engine and only replace energy computation.
@_spi(Backend)
public struct CoreResizeEngine: Sendable {
    private let backwardEnergyProvider: any BackwardEnergyProvider

    public init(backwardEnergyProvider: any BackwardEnergyProvider) {
        self.backwardEnergyProvider = backwardEnergyProvider
    }

    public func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions
    ) async throws -> SeamPath {
        try findSeam(in: image, orientation: orientation, energyMode: options.energyMode, masks: options.masks, blurRadius: options.blurRadius, sobelThreshold: options.sobelThreshold, recorder: nil)
    }

    private func findSeam(
        in image: RGBA8Image,
        orientation: SeamOrientation,
        energyMode: EnergyMode,
        masks: MaskPair,
        blurRadius: Int,
        sobelThreshold: Float,
        recorder: BackendTimingRecorder?
    ) throws -> SeamPath {
        guard blurRadius >= 0 else {
            throw SeamCarvingError.invalidConfiguration("blur radius must be nonnegative")
        }
        guard sobelThreshold.isFinite, sobelThreshold >= 0 else {
            throw SeamCarvingError.invalidConfiguration("Sobel threshold must be finite and nonnegative")
        }
        switch energyMode {
        case .backwardSobel:
            let base = try measure(recorder, phase: \.energyNS) {
                try backwardEnergyProvider.compute(for: image, blurRadius: blurRadius, sobelThreshold: sobelThreshold)
            }
            let adjustment = try measure(recorder, phase: \.maskNS) {
                try masks.energyAdjustment(forWidth: image.width, height: image.height)
            }
            if let adjustment {
                let adjusted = try base.adding(adjustment)
                return try measure(recorder, phase: \.dynamicProgrammingNS) {
                    try DynamicProgramming.findSeam(in: adjusted, orientation: orientation)
                }
            }
            return try measure(recorder, phase: \.dynamicProgrammingNS) {
                try DynamicProgramming.findSeam(in: base, orientation: orientation)
            }
        case .forwardLuma:
            if blurRadius > 0 || sobelThreshold > 0 {
                throw SeamCarvingError.invalidConfiguration(
                    "blur radius and Sobel threshold require backward Sobel energy"
                )
            }
            let luminance = try measure(recorder, phase: \.energyNS) {
                try LuminancePlane.luma(of: image)
            }
            let adjustment = try measure(recorder, phase: \.maskNS) {
                try masks.energyAdjustment(forWidth: image.width, height: image.height)
            }
            return try measure(recorder, phase: \.dynamicProgrammingNS) {
                try ForwardEnergy.findSeam(in: luminance, orientation: orientation, adjustedBaseEnergy: adjustment)
            }
        }
    }

    private func measure<T>(
        _ recorder: BackendTimingRecorder?,
        phase: WritableKeyPath<BackendPhaseDurations, UInt64>,
        _ body: () throws -> T
    ) rethrows -> T {
        guard let recorder else { return try body() }
        return try recorder.measure(phase, body)
    }

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions
    ) async throws -> RGBA8Image {
        try await resize(image, to: target, options: options, recorder: nil)
    }

    @_spi(Benchmark)
    public func resizeInstrumented(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        recorder: BackendTimingRecorder
    ) async throws -> RGBA8Image {
        try await resize(image, to: target, options: options, recorder: recorder)
    }

    private func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions,
        recorder: BackendTimingRecorder?
    ) async throws -> RGBA8Image {
        try options.masks.validateDimensions(width: image.width, height: image.height)

        let widthDelta = target.width - image.width
        let heightDelta = target.height - image.height
        let totalEdits = abs(widthDelta) + abs(heightDelta)

        var current = image
        var currentMasks = options.masks
        var completed = 0

        switch options.dimensionOrder {
        case .widthThenHeight:
            (current, currentMasks, completed) = try await applyDimension(
                .vertical, delta: widthDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits, recorder: recorder
            )
            (current, currentMasks, completed) = try await applyDimension(
                .horizontal, delta: heightDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits, recorder: recorder
            )
        case .heightThenWidth:
            (current, currentMasks, completed) = try await applyDimension(
                .horizontal, delta: heightDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits, recorder: recorder
            )
            (current, currentMasks, completed) = try await applyDimension(
                .vertical, delta: widthDelta, to: current, masks: currentMasks,
                options: options, completed: completed, totalEdits: totalEdits, recorder: recorder
            )
        case .adaptiveNormalizedCost:
            var remainingWidth = widthDelta
            var remainingHeight = heightDelta
            while remainingWidth != 0 || remainingHeight != 0 {
                try Task.checkCancellation()
                let orientation: SeamOrientation
                if remainingWidth == 0 {
                    orientation = .horizontal
                } else if remainingHeight == 0 {
                    orientation = .vertical
                } else {
                    let vertical = try findSeam(in: current, orientation: .vertical, energyMode: options.energyMode, masks: currentMasks, blurRadius: options.blurRadius, sobelThreshold: options.sobelThreshold, recorder: recorder)
                    let horizontal = try findSeam(in: current, orientation: .horizontal, energyMode: options.energyMode, masks: currentMasks, blurRadius: options.blurRadius, sobelThreshold: options.sobelThreshold, recorder: recorder)
                    let verticalNormalized = vertical.totalCost / Float(current.height)
                    let horizontalNormalized = horizontal.totalCost / Float(current.width)
                    orientation = verticalNormalized <= horizontalNormalized ? .vertical : .horizontal
                }
                let step = (orientation == .vertical ? remainingWidth : remainingHeight) > 0 ? 1 : -1
                (current, currentMasks, completed) = try await applyDimension(
                    orientation, delta: step, to: current, masks: currentMasks,
                    options: options, completed: completed, totalEdits: totalEdits, recorder: recorder
                )
                if orientation == .vertical {
                    remainingWidth -= step
                } else {
                    remainingHeight -= step
                }
            }
        }

        return current
    }

    // MARK: - Dimension application

    private func applyDimension(
        _ orientation: SeamOrientation,
        delta: Int,
        to image: RGBA8Image,
        masks: MaskPair,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int,
        recorder: BackendTimingRecorder?
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        if delta < 0 {
            return try await shrinkDimension(image, masks: masks, count: -delta, orientation: orientation, options: options, completed: completed, totalEdits: totalEdits, recorder: recorder)
        }
        if delta > 0 {
            return try await enlargeDimension(image, masks: masks, count: delta, orientation: orientation, options: options, completed: completed, totalEdits: totalEdits, recorder: recorder)
        }
        return (image, masks, completed)
    }

    private func shrinkDimension(
        _ image: RGBA8Image,
        masks: MaskPair,
        count: Int,
        orientation: SeamOrientation,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int,
        recorder: BackendTimingRecorder?
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        var current = image
        var currentMasks = masks
        var completed = completed
        for _ in 0..<count {
            try Task.checkCancellation()
            let seam = try findSeam(in: current, orientation: orientation, energyMode: options.energyMode, masks: currentMasks, blurRadius: options.blurRadius, sobelThreshold: options.sobelThreshold, recorder: recorder)
            if let recorder {
                current = try recorder.measure(\.editNS) { try SeamEditor.remove(seam, from: current) }
                currentMasks = try recorder.measure(\.maskNS) { try removing(seam, from: currentMasks) }
            } else {
                current = try SeamEditor.remove(seam, from: current)
                currentMasks = try removing(seam, from: currentMasks)
            }
            completed += 1
            options.progress?(ResizeProgress(completedEdits: completed, totalEdits: totalEdits, size: try PixelSize(width: current.width, height: current.height)))
        }
        return (current, currentMasks, completed)
    }

    private func enlargeDimension(
        _ image: RGBA8Image,
        masks: MaskPair,
        count: Int,
        orientation: SeamOrientation,
        options: ResizeOptions,
        completed: Int,
        totalEdits: Int,
        recorder: BackendTimingRecorder?
    ) async throws -> (image: RGBA8Image, masks: MaskPair, completed: Int) {
        var current = image
        var currentMasks = masks
        var completed = completed
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            let dimension = orientation == .vertical ? current.width : current.height
            let set: MappedSeamSet
            if dimension == 1 {
                let soleLength = orientation == .vertical ? current.height : current.width
                set = try MappedSeamSet(orientation: orientation, coordinatesBySeam: [[UInt32](repeating: 0, count: soleLength)])
            } else {
                let batchSize = min(remaining, dimension - 1)
                var opts = options
                opts.masks = currentMasks
                set = try await discoverMappedSeams(count: batchSize, in: current, orientation: orientation, options: opts, recorder: recorder)
            }

            let inserted: (image: RGBA8Image, masks: MaskPair)
            if let recorder {
                inserted = try recorder.measure(\.editNS) { try insertMapped(set, into: current, masks: currentMasks) }
            } else {
                inserted = try insertMapped(set, into: current, masks: currentMasks)
            }
            current = inserted.image
            currentMasks = inserted.masks
            remaining -= set.coordinatesBySeam.count
            completed += set.coordinatesBySeam.count
            options.progress?(ResizeProgress(completedEdits: completed, totalEdits: totalEdits, size: try PixelSize(width: current.width, height: current.height)))
        }
        return (current, currentMasks, completed)
    }

    // MARK: - Mapped seam discovery

    func discoverMappedVerticalSeams(count: Int, in image: RGBA8Image, options: ResizeOptions, recorder: BackendTimingRecorder? = nil) async throws -> MappedSeamSet {
        let width = image.width
        let height = image.height
        guard count > 0, count < width else {
            throw SeamCarvingError.invalidConfiguration("seam count must be in 1..<width")
        }

        var working = image
        var workingMasks = options.masks
        var indexMap = [UInt32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                indexMap[y * width + x] = UInt32(x)
            }
        }

        var seams: [[UInt32]] = []
        seams.reserveCapacity(count)
        for _ in 0..<count {
            try Task.checkCancellation()
            let currentWidth = working.width
            let seam = try findSeam(in: working, orientation: .vertical, energyMode: options.energyMode, masks: workingMasks, blurRadius: options.blurRadius, sobelThreshold: options.sobelThreshold, recorder: recorder)
            let mapped = seam.coordinates.enumerated().map { indexMap[$0.offset * currentWidth + Int($0.element)] }
            seams.append(mapped)
            if let recorder {
                working = try recorder.measure(\.editNS) { try SeamEditor.remove(seam, from: working) }
                workingMasks = try recorder.measure(\.maskNS) { try removing(seam, from: workingMasks) }
            } else {
                working = try SeamEditor.remove(seam, from: working)
                workingMasks = try removing(seam, from: workingMasks)
            }
            indexMap = try removeVerticalSeam(indexMap, seam: seam, width: currentWidth)
        }
        return try MappedSeamSet(orientation: .vertical, coordinatesBySeam: seams)
    }

    private func removeVerticalSeam(_ indexMap: [UInt32], seam: SeamPath, width: Int) throws -> [UInt32] {
        let height = seam.coordinates.count
        var result = [UInt32]()
        result.reserveCapacity((width - 1) * height)
        for y in 0..<height {
            let removeAt = Int(seam.coordinates[y])
            let rowStart = y * width
            result.append(contentsOf: indexMap[rowStart..<(rowStart + removeAt)])
            result.append(contentsOf: indexMap[(rowStart + removeAt + 1)..<(rowStart + width)])
        }
        return result
    }

    // MARK: - Insertion

    private func insertMapped(
        _ set: MappedSeamSet,
        into image: RGBA8Image,
        masks: MaskPair
    ) throws -> (image: RGBA8Image, masks: MaskPair) {
        switch set.orientation {
        case .vertical:
            let newImage = try SeamEditor.insertMappedVerticalSeams(set.coordinatesBySeam, into: image, policy: .neighborAverage)
            let newMasks = try inserting(set.coordinatesBySeam, into: masks)
            return (newImage, newMasks)
        case .horizontal:
            let transposedImage = try SeamEditor.transpose(image)
            let transposedMasks = try transposeMaskPair(masks)
            let insertedImage = try SeamEditor.insertMappedVerticalSeams(set.coordinatesBySeam, into: transposedImage, policy: .neighborAverage)
            let insertedMasks = try inserting(set.coordinatesBySeam, into: transposedMasks)
            return (try SeamEditor.transpose(insertedImage), try transposeMaskPair(insertedMasks))
        }
    }

    /// Inserts mapped vertical seams into every mask layer, preserving strength.
    private func inserting(_ seams: [[UInt32]], into masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try SeamEditor.insertMappedVerticalSeams(seams, into: layer.mask)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.insertMappedVerticalSeams(seams, into: removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }

    /// Removes a seam from every layer of a mask pair, preserving strength.
    private func removing(_ seam: SeamPath, from masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            let newMask = try SeamEditor.remove(seam, from: layer.mask)
            newProtection.append(try ProtectionLayer(mask: newMask, strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.remove(seam, from: removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }

    func transposeMaskPair(_ masks: MaskPair) throws -> MaskPair {
        var newProtection: [ProtectionLayer] = []
        for layer in masks.protectionLayers {
            newProtection.append(try ProtectionLayer(mask: try SeamEditor.transpose(layer.mask), strength: layer.strength))
        }
        let newRemoval: Mask?
        if let removal = masks.removal {
            newRemoval = try SeamEditor.transpose(removal)
        } else {
            newRemoval = nil
        }
        return try MaskPair(protectionLayers: newProtection, removal: newRemoval, removalWeight: masks.removalWeight)
    }
}

@_spi(Backend)
public extension CoreResizeEngine {
    /// Discovers `count` seams mapped to original-image coordinates. Horizontal
    /// discovery transposes image and masks, runs vertical discovery, and re-labels.
    func discoverMappedSeams(
        count: Int,
        in image: RGBA8Image,
        orientation: SeamOrientation,
        options: ResizeOptions,
        recorder: BackendTimingRecorder? = nil
    ) async throws -> MappedSeamSet {
        try options.masks.validateDimensions(width: image.width, height: image.height)
        switch orientation {
        case .vertical:
            return try await discoverMappedVerticalSeams(count: count, in: image, options: options, recorder: recorder)
        case .horizontal:
            let transposedImage = try SeamEditor.transpose(image)
            var transposedOptions = options
            transposedOptions.masks = try transposeMaskPair(options.masks)
            let set = try await discoverMappedVerticalSeams(count: count, in: transposedImage, options: transposedOptions, recorder: recorder)
            return try MappedSeamSet(orientation: .horizontal, coordinatesBySeam: set.coordinatesBySeam)
        }
    }
}
