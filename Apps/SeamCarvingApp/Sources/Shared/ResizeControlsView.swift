// ResizeControlsView.swift
//
// Binds the resize configuration fields to editable controls. All mutations go
// through the @Observable `AppModel.configuration` on the main actor. No
// image-processing logic lives here.

import Foundation
import SeamCarvingCore
import SwiftUI

struct ResizeControlsView: View {
    @Bindable var model: AppModel

    /// When locked, editing one dimension scales the other to preserve ratio.
    @State private var lockAspect: Bool = false

    /// Source ratio used by the aspect lock (captured from the document).
    private var aspectRatio: Double? {
        guard let doc = model.document else { return nil }
        guard doc.sourceSize.height > 0 else { return nil }
        return Double(doc.sourceSize.width) / Double(doc.sourceSize.height)
    }

    var body: some View {
        Form {
            Section(A11y.Label.controls) {
                targetSizeFields
                Toggle(A11y.Label.lockAspect, isOn: $lockAspect)
                    .accessibilityIdentifier(A11y.ID.lockAspect)
                backendExplanation
            }
            Section("Algorithm") {
                Picker(A11y.Label.energyMode, selection: $model.configuration.energyMode) {
                    Text("Backward Sobel").tag(EnergyMode.backwardSobel)
                    Text("Forward Luma").tag(EnergyMode.forwardLuma)
                }
                .accessibilityIdentifier(A11y.ID.energyMode)

                Picker(A11y.Label.dimensionOrder, selection: $model.configuration.dimensionOrder) {
                    Text("Width then Height").tag(DimensionOrder.widthThenHeight)
                    Text("Height then Width").tag(DimensionOrder.heightThenWidth)
                    Text("Adaptive").tag(DimensionOrder.adaptiveNormalizedCost)
                }
                .accessibilityIdentifier(A11y.ID.dimensionOrder)
            }
            Section("Backend") {
                Picker(A11y.Label.backend, selection: $model.configuration.backend) {
                    Text("Automatic").tag(BackendPreference.automatic)
                    Text("CPU").tag(BackendPreference.cpu)
                    Text("Accelerate").tag(BackendPreference.accelerate)
                    Text("Metal").tag(BackendPreference.metal)
                }
                .accessibilityIdentifier(A11y.ID.backend)

                Toggle(A11y.Label.deterministic, isOn: $model.configuration.deterministic)
                    .accessibilityIdentifier(A11y.ID.deterministic)

                Picker(A11y.Label.preScale, selection: $model.configuration.preScaleStrategy) {
                    Text("None").tag(PreScaleStrategy.none)
                    Text("Lanczos + exact residual").tag(PreScaleStrategy.lanczosThenExactResidual)
                }
                .accessibilityIdentifier(A11y.ID.preScale)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.ID.controls)
        .disabled(model.phase.isProcessing)
    }

    @ViewBuilder
    private var targetSizeFields: some View {
        Stepper(value: widthBinding, in: 1...8192) {
            targetField(label: A11y.Label.targetWidth, value: widthBinding, other: heightBinding)
        }
        .accessibilityIdentifier(A11y.ID.targetWidth)

        Stepper(value: heightBinding, in: 1...8192) {
            targetField(label: A11y.Label.targetHeight, value: heightBinding, other: widthBinding)
        }
        .accessibilityIdentifier(A11y.ID.targetHeight)
    }

    /// `PixelSize` stores `let` width/height, so we expose mutable bindings that
    /// rebuild an immutable `PixelSize` on write.
    private var widthBinding: Binding<Int> {
        Binding {
            model.configuration.targetSize.width
        } set: { newValue in
            model.configuration.targetSize = try! PixelSize(width: newValue, height: model.configuration.targetSize.height)
        }
    }

    private var heightBinding: Binding<Int> {
        Binding {
            model.configuration.targetSize.height
        } set: { newValue in
            model.configuration.targetSize = try! PixelSize(width: model.configuration.targetSize.width, height: newValue)
        }
    }

    private func targetField(
        label: String,
        value: Binding<Int>,
        other: Binding<Int>
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { _, newValue in
                    guard lockAspect, let ratio = aspectRatio, ratio > 0 else { return }
                    if label == A11y.Label.targetWidth {
                        other.wrappedValue = max(1, Int(Double(newValue) / ratio))
                    } else {
                        other.wrappedValue = max(1, Int(Double(newValue) * ratio))
                    }
                }
        }
    }

    /// Derived helper text explaining which backend will actually be used.
    private var backendExplanationText: String {
        switch (model.configuration.backend, model.configuration.deterministic) {
        case (.automatic, false):
            return "Automatic picks Metal when available, else Accelerate/CPU. Non-deterministic is fastest."
        case (.automatic, true):
            return "Automatic with deterministic forces a CPU/Accelerate path with reproducible results."
        case (.metal, _):
            return "Metal GPU backend. Falls back to CPU if Metal is unavailable on this device."
        case (.accelerate, _):
            return "Apple Accelerate (vDSP) backend."
        case (.cpu, _):
            return "Pure-CPU backend. Slowest, but always available and fully deterministic-safe."
        }
    }

    @ViewBuilder
    private var backendExplanation: some View {
        let text = backendExplanationText
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Backend note: \(text)")
    }
}

extension ResizePhase {
    /// True while a resize is in flight; controls are disabled during this phase.
    var isProcessing: Bool {
        if case .resizing = self { return true }
        return false
    }
}
