// ContentView.swift
//
// The root shared editor. On a regular size class (macOS, iPad) it uses a
// NavigationSplitView (sidebar controls + detail canvas); on compact (iPhone)
// it collapses to a single NavigationStack. The AppModel is owned at the root
// and passed down via `@Bindable` / environment. Carving runs in the model's
// async service; the view only observes `phase`, never blocking the main actor.

import Foundation
import SwiftUI

#if os(iOS)
import PhotosUI
import UIKit
import UniformTypeIdentifiers
#endif

enum EditorLayout {
    static let sidebarMinWidth: CGFloat = 280
    static let sidebarIdealWidth: CGFloat = 320
    static let sidebarMaxWidth: CGFloat = 380
    static let detailMinWidth: CGFloat = 420
    static let compactCanvasMinHeight: CGFloat = 280
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var painter = MaskPaintingController()
    @State private var maskMode: MaskMode = .protect
#if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingFileImporter = false
#endif

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .accessibilityIdentifier(A11y.ID.contentView)
        .task { bindPainter() }
        .onChange(of: model.phase) { _, _ in
            if let doc = model.document { painter.bind(doc) }
        }
    }

    private func bindPainter() {
        if let doc = model.document { painter.bind(doc) }
    }

    // MARK: - Regular (split) layout

    @ViewBuilder
    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: EditorLayout.sidebarMinWidth,
                    ideal: EditorLayout.sidebarIdealWidth,
                    max: EditorLayout.sidebarMaxWidth
                )
        } detail: {
            detail
                .frame(minWidth: EditorLayout.detailMinWidth)
        }
    }

    // MARK: - Compact (stack) layout

    @ViewBuilder
    private var stackLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    detail
                    sidebar
                }
            }
            .navigationTitle("Seam Carving")
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                importButton
                ResizeControlsView(model: model)
                MaskToolbarView(model: model, painter: painter, mode: $maskMode)
                FaceProtectionControlsView(model: model)
                CarveProgressView(model: model)
                ExportView(model: model)
                resizeButton
                if let error = model.errorMessage, model.phase == .failed {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var detail: some View {
        ImageCanvasView(model: model, painter: painter, mode: $maskMode)
            .frame(maxWidth: .infinity, minHeight: EditorLayout.compactCanvasMinHeight)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var resizeButton: some View {
        Button(A11y.Label.resize) { model.resize() }
            .accessibilityIdentifier(A11y.ID.resize)
            .disabled(model.phase.isProcessing || model.document == nil)
            .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var importButton: some View {
#if os(macOS)
        Button("Import Image…") {
            guard let source = MacPlatformServices.openImage() else { return }
            Task { await model.importImage(source) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(A11y.ID.importButton)
#elseif os(iOS)
        HStack {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Photos", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.bordered)
            Button("Files…", systemImage: "folder") { isShowingFileImporter = true }
                .buttonStyle(.bordered)
        }
        .accessibilityIdentifier(A11y.ID.importButton)
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
                await model.importImage(ApplePlatformServices.imageSource(from: image))
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await model.importImage(ApplePlatformServices.imageSource(from: image))
            }
        }
#else
        EmptyView()
#endif
    }
}
