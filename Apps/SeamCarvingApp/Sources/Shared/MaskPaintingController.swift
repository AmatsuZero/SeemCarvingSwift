// MaskPaintingController.swift
//
// A small @MainActor controller that owns the undo/redo history for mask edits
// and applies brush strokes in canonical image-pixel coordinates. It is kept
// app-layer (no seam-carving math) and deliberately separate from the engine:
// it only reads/writes `MaskPair` on the bound `ResizeDocument`.

import Foundation
import SeamCarvingCore

/// The active painting mode for the mask toolbar.
enum MaskMode: Sendable, Equatable {
    case protect
    case remove
    case erase
}

/// Owns the local undo/redo stack of mask states and applies strokes. The
/// document's `currentMasks` is the single source of truth; this controller
/// snapshots it before each committed stroke.
@MainActor
@Observable
final class MaskPaintingController {
    private weak var document: ResizeDocument?
    private var undoStack: [MaskPair] = []
    private var redoStack: [MaskPair] = []

    /// A clamped brush radius (in image pixels) and a 0...1 strength.
    var brushRadius: Int = 12
    var strength: Float = 1.0

    init(document: ResizeDocument? = nil) {
        self.document = document
    }

    func bind(_ document: ResizeDocument) {
        self.document = document
        undoStack.removeAll()
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - History

    /// Pushes the current mask state so a subsequent `commit` can be undone.
    private func pushUndo() {
        guard let masks = document?.currentMasks else { return }
        undoStack.append(masks)
        // Bound memory; deeper history is dropped from the oldest end.
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let current = document?.currentMasks, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        document?.currentMasks = previous
    }

    func redo() {
        guard let current = document?.currentMasks, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        document?.currentMasks = next
    }

    /// Resets masks to empty while remembering the prior state for undo.
    func clear() {
        pushUndo()
        document?.currentMasks = MaskPair()
    }

    /// Re-applies the document's original (source-derived) empty state. For now
    /// this is identical to `clear`; exposed separately so the UI can label the
    /// intent distinctly.
    func reset() {
        pushUndo()
        document?.currentMasks = MaskPair()
    }

    // MARK: - Painting (canonical coordinates)

    /// Paints a single dab at an image-pixel coordinate. The caller (the canvas)
    /// is responsible for converting gesture/view space into canonical pixels
    /// and passing a valid in-bounds `pixelX`/`pixelY`. This keeps all geometry
    /// math at the canvas boundary and never in the engine.
    func paintDab(at pixelX: Int, _ pixelY: Int, mode: MaskMode) {
        guard let doc = document else { return }
        let w = doc.sourceSize.width
        let h = doc.sourceSize.height
        guard pixelX >= 0, pixelY >= 0, pixelX < w, pixelY < h else { return }

        pushUndo()

        let masks = doc.currentMasks
        switch mode {
        case .protect:
            doc.currentMasks = masks.appendingProtection(
                paintingAt: pixelX, pixelY, radius: brushRadius, strength: strength
            )
        case .remove:
            doc.currentMasks = masks.replacingRemoval(
                paintingAt: pixelX, pixelY, radius: brushRadius, strength: strength
            )
        case .erase:
            doc.currentMasks = masks.erasing(at: pixelX, pixelY, radius: brushRadius)
        }
    }

    /// Commits a multi-dab stroke by coalescing the undo step. Called when a
    /// drag gesture ends so the whole stroke is a single undo unit.
    func beginStroke() {
        pushUndo()
    }

    func endStroke() {
        // The `beginStroke` already pushed the pre-stroke snapshot; nothing else
        // is required, but this marker documents the stroke boundary.
    }
}

// MARK: - MaskPair painting extensions (canonical pixel math only)

extension MaskPair {
    /// Returns a copy with a soft-protection layer painted at the given dab.
    fileprivate func appendingProtection(
        paintingAt x: Int, _ y: Int, radius: Int, strength: Float
    ) -> MaskPair {
        var values: [Float]
        if let first = protectionLayers.first {
            values = first.mask.values
        } else {
            values = [Float](repeating: 0, count: widthOfFirst ?? 0)
        }
        paintInto(&values, x: x, y, radius: radius, delta: strength)
        let mask = try? Mask(width: widthOfFirst ?? 1, height: heightOfFirst ?? 1, values: values)
        guard let mask else { return self }
        let layer = try? ProtectionLayer(mask: mask, strength: .soft(strength))
        let newLayers = (layer.map { [$0] } ?? []) + protectionLayers.dropFirst()
        return (try? MaskPair(protectionLayers: newLayers, removal: removal, removalWeight: removalWeight)) ?? self
    }

    /// Returns a copy with the removal mask painted at the given dab.
    fileprivate func replacingRemoval(
        paintingAt x: Int, _ y: Int, radius: Int, strength: Float
    ) -> MaskPair {
        let w = removal?.width ?? widthOfFirst ?? 1
        let h = removal?.height ?? heightOfFirst ?? 1
        var values = removal?.values ?? [Float](repeating: 0, count: w * h)
        paintInto(&values, x: x, y, radius: radius, delta: strength)
        let mask = try? Mask(width: w, height: h, values: values)
        return (try? MaskPair(protectionLayers: protectionLayers, removal: mask, removalWeight: removalWeight)) ?? self
    }

    /// Returns a copy with both protection and removal set toward zero at the dab.
    fileprivate func erasing(at x: Int, _ y: Int, radius: Int) -> MaskPair {
        let newLayers = protectionLayers.compactMap { layer -> ProtectionLayer? in
            var values = layer.mask.values
            paintInto(&values, x: x, y, radius: radius, delta: -1)
            let mask = try? Mask(width: layer.mask.width, height: layer.mask.height, values: values)
            return mask.map { try? ProtectionLayer(mask: $0, strength: layer.strength) } ?? layer
        }
        var removalValues = removal?.values
        if removalValues != nil {
            paintInto(&removalValues!, x: x, y, radius: radius, delta: -1)
        }
        let newRemoval = removalValues.map { try? Mask(width: removal!.width, height: removal!.height, values: $0) } ?? removal
        return (try? MaskPair(protectionLayers: newLayers, removal: newRemoval, removalWeight: removalWeight)) ?? self
    }

    private var widthOfFirst: Int? { protectionLayers.first?.mask.width }
    private var heightOfFirst: Int? { protectionLayers.first?.mask.height }

    /// Mutates `values` (row-major Float, 0...1) by stamping a soft circular dab.
    private func paintInto(_ values: inout [Float], x: Int, _ y: Int, radius: Int, delta: Float) {
        guard let w = widthOfFirst ?? removal?.width, let h = heightOfFirst ?? removal?.height else { return }
        let r = max(1, radius)
        let x0 = max(0, x - r), x1 = min(w - 1, x + r)
        let y0 = max(0, y - r), y1 = min(h - 1, y + r)
        let r2 = Float(r * r)
        for py in y0...y1 {
            for px in x0...x1 {
                let dx = Float(px - x), dy = Float(py - y)
                let dist2 = dx * dx + dy * dy
                if dist2 > r2 { continue }
                // Soft falloff: 1 at center, 0 at edge.
                let falloff = 1 - (dist2 / max(r2, 1e-6))
                let idx = py * w + px
                let applied = delta >= 0 ? delta * falloff : falloff
                if delta >= 0 {
                    values[idx] = min(1, values[idx] + applied)
                } else {
                    values[idx] = max(0, values[idx] - applied)
                }
            }
        }
    }
}
