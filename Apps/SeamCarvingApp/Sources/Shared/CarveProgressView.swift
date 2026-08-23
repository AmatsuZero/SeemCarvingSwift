// CarveProgressView.swift
//
// Progress + cancellation UI for an in-flight resize. Shows current dimensions,
// completed/total edits, the backend in use, and a Cancel action. Named
// `CarveProgressView` to avoid clashing with `SwiftUI.ProgressView`.

import Foundation
import SeamCarvingCore
import SwiftUI

struct CarveProgressView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.phase.isProcessing {
            VStack(alignment: .leading, spacing: 8) {
                if let progress = currentProgress {
                    Text("\(progress.size.width)×\(progress.size.height) · \(progress.completedEdits)/\(progress.totalEdits) edits")
                        .accessibilityIdentifier(A11y.ID.progress)
                    ProgressView(value: Double(progress.completedEdits), total: Double(max(1, progress.totalEdits)))
                } else {
                    Text("Starting…")
                        .accessibilityIdentifier(A11y.ID.progress)
                    ProgressView()
                }
                Text("Backend: \(backendLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(A11y.Label.cancel) { model.cancelResize() }
                    .accessibilityIdentifier(A11y.ID.cancel)
                    .buttonStyle(EditorActionButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(A11y.Label.progress)
        } else if case .cancelled = model.phase {
            Label("Cancelled — source and masks retained", systemImage: "xmark.circle")
                .accessibilityLabel("Resize cancelled")
        }
    }

    private var currentProgress: ResizeProgress? {
        if case .resizing(let p) = model.phase { return p }
        return nil
    }

    private var backendLabel: String {
        if case .resizing = model.phase {
            switch model.configuration.backend {
            case .automatic: return model.configuration.deterministic ? "Automatic (deterministic)" : "Automatic"
            case .cpu: return "CPU"
            case .accelerate: return "Accelerate"
            case .metal: return "Metal"
            }
        }
        return "—"
    }
}
