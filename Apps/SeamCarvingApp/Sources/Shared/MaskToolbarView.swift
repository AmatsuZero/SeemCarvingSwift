// MaskToolbarView.swift
//
// The mask painting toolbar: mode selection (protect/remove/erase), brush size,
// strength/opacity, undo/redo, clear, and reset. Edits are delegated to the
// `MaskPaintingController`, which stores masks in canonical pixel coordinates on
// the document. No carving logic here.

import Foundation
import SwiftUI

struct MaskToolbarView: View {
    @Bindable var model: AppModel
    var painter: MaskPaintingController
    @Binding var mode: MaskMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modePicker
            brushControls
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.ID.maskToolbar)
        .disabled(model.phase.isProcessing)
    }

    @ViewBuilder
    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Label(A11y.Label.protect, systemImage: "shield").tag(MaskMode.protect)
            Label(A11y.Label.remove, systemImage: "trash").tag(MaskMode.remove)
            Label(A11y.Label.erase, systemImage: "eraser").tag(MaskMode.erase)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(A11y.ID.maskModeProtect) // group id; buttons below
    }

    @ViewBuilder
    private var brushControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(A11y.Label.brushSize)
                Slider(value: Binding(
                    get: { Double(painter.brushRadius) },
                    set: { painter.brushRadius = max(1, Int($0)) }
                ), in: 1...80, step: 1)
                .accessibilityIdentifier(A11y.ID.brushSize)
                Text("\(painter.brushRadius)").frame(width: 36)
            }
            if mode != .erase {
                HStack {
                    Text(A11y.Label.strength)
                    Slider(value: Binding(
                        get: { Double(painter.strength) },
                        set: { painter.strength = Float($0) }
                    ), in: 0...1, step: 0.05)
                    .accessibilityIdentifier(A11y.ID.brushStrength)
                    Text(String(format: "%.2f", painter.strength)).frame(width: 44)
                }
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Button {
                painter.undo()
            } label: {
                Text(A11y.Label.undo).lineLimit(1).minimumScaleFactor(0.8)
            }
                .accessibilityIdentifier(A11y.ID.undo)
                .disabled(!painter.canUndo)
            Button {
                painter.redo()
            } label: {
                Text(A11y.Label.redo).lineLimit(1).minimumScaleFactor(0.8)
            }
                .accessibilityIdentifier(A11y.ID.redo)
                .disabled(!painter.canRedo)
            Spacer()
            Button {
                painter.clear()
            } label: {
                Text(A11y.Label.clear).lineLimit(1).minimumScaleFactor(0.8)
            }
                .accessibilityIdentifier(A11y.ID.clearMasks)
            Button {
                painter.reset()
            } label: {
                Text(A11y.Label.reset).lineLimit(1).minimumScaleFactor(0.8)
            }
                .accessibilityIdentifier(A11y.ID.resetMasks)
        }
    }
}
