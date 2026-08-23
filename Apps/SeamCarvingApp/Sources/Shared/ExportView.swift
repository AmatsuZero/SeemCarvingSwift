// ExportView.swift
//
// Export affordance. Reflects the model phase and triggers `model.export()`.
// The actual encoding is delegated to the model (Task 3 already encodes PNG
// bytes). This view holds no image-processing logic.

import Foundation
import SwiftUI

struct ExportView: View {
    @Bindable var model: AppModel
    var onExported: ((Data, ExportFormat) -> Void)? = nil
    @State private var format: ExportFormat = .png

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { value in
                    Text(value.rawValue.uppercased()).tag(value)
                }
            }
            .pickerStyle(.segmented)
            Button(A11y.Label.exportButton) {
                Task {
                    await model.export(format: format)
                    if let data = model.document?.exportedData {
                        onExported?(data, format)
                    }
                }
            }
                .accessibilityIdentifier(A11y.ID.exportButton)
                .disabled(!canExport)
                .buttonStyle(.borderedProminent)

            if let meta = model.document?.exportMetadata {
                Text("Exported \(meta.format.uppercased()) · \(meta.byteCount) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
#if os(iOS)
            if let data = model.document?.exportedData {
                ShareLink(item: data, preview: SharePreview("Seam Carving Export", image: Image(systemName: "photo"))) {
                    Label("Share Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export.share")
            }
#endif
            if let error = model.errorMessage, model.phase == .failed {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.ID.export)
    }

    /// Export is only valid once a carve has completed.
    private var canExport: Bool {
        if case .completed = model.phase { return model.document?.workingImage != nil }
        return false
    }
}
