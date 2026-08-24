// ImageCanvasView.swift
//
// Displays the source (and, after a carve, the working) image preserving aspect
// ratio, and translates drag gestures from view space into canonical image-pixel
// coordinates for mask painting. All geometry conversion happens here at the
// canvas boundary; nothing downstream touches view coordinates.

import CoreGraphics
import Foundation
import SeamCarvingAppleImaging
import SeamCarvingCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

struct ImageCanvasView: View {
    @Bindable var model: AppModel
    var painter: MaskPaintingController

    /// The active painting mode, owned by the toolbar but read here for gestures.
    @Binding var mode: MaskMode

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let doc = model.document {
                    let image = model.workingImageOrNil ?? doc.sourceImage
                    let rect = fittedRect(imageSize: CGSize(width: image.width, height: image.height), in: geo.size)
                    Canvas { ctx, size in
                        draw(image: image, rect: rect, in: ctx, size: size)
                    }
                    .accessibilityLabel(A11y.Label.canvas)
                    .accessibilityIdentifier(A11y.ID.canvas)
                    .gesture(paintGesture(in: geo.size, image: image))
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11y.Label.canvas)
        .accessibilityIdentifier(A11y.ID.canvas)
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.largeTitle)
            Text("Import an image to begin")
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(A11y.ID.canvasPlaceholder)
    }

    // MARK: - Drawing (aspect preserving)

    private func draw(image: RGBA8Image, rect: CGRect, in ctx: GraphicsContext, size: CGSize) {
        guard let cgImage = try? CGImageBridge.encode(image) else { return }
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: image.width, height: image.height))
        ctx.draw(Image(nsImage: nsImage), in: rect)
        #elseif canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        ctx.draw(Image(uiImage: uiImage), in: rect)
        #endif
        // Overlay the protection/removal masks faintly so the user sees what is set.
        drawMaskOverlay(in: ctx, rect: rect)
        drawFaceOverlay(in: ctx, rect: rect)
    }

    private func drawMaskOverlay(in ctx: GraphicsContext, rect: CGRect) {
        guard let doc = model.document else { return }
        let masks = doc.currentMasks
        let w = doc.sourceSize.width
        let h = doc.sourceSize.height
        let scaleX = rect.width / CGFloat(w)
        let scaleY = rect.height / CGFloat(h)

        if let removal = masks.removal {
            let path = maskPath(removal, rect: rect, scaleX: scaleX, scaleY: scaleY, w: w, h: h)
            ctx.fill(path, with: .color(.red.opacity(0.3)))
        }
        if let first = masks.protectionLayers.first {
            let path = maskPath(first.mask, rect: rect, scaleX: scaleX, scaleY: scaleY, w: w, h: h)
            ctx.fill(path, with: .color(.blue.opacity(0.3)))
        }
    }

    private func drawFaceOverlay(in ctx: GraphicsContext, rect: CGRect) {
        guard let doc = model.document else { return }
        let regions = model.configuration.faceProtection?.detectedRegions ?? doc.faceRegions ?? []
        guard !regions.isEmpty else { return }
        let protectedIDs = Set(model.configuration.faceProtection?.effectiveRegions.map(\.stableID) ?? [])
        let scaleX = rect.width / CGFloat(doc.sourceSize.width)
        let scaleY = rect.height / CGFloat(doc.sourceSize.height)
        for region in regions {
            let box = CGRect(
                x: rect.minX + CGFloat(region.x) * scaleX,
                y: rect.minY + CGFloat(region.y) * scaleY,
                width: CGFloat(region.width) * scaleX,
                height: CGFloat(region.height) * scaleY
            )
            var path = Path()
            path.addRect(box)
            let color: Color = protectedIDs.contains(region.stableID) ? .green : .orange
            ctx.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 2)
        }
    }

    /// Builds a path covering every pixel whose mask value exceeds a small
    /// threshold, scaled into the displayed image rect.
    private func maskPath(_ mask: Mask, rect: CGRect, scaleX: CGFloat, scaleY: CGFloat, w: Int, h: Int) -> Path {
        var path = Path()
        for y in 0..<min(h, mask.height) {
            for x in 0..<min(w, mask.width) {
                if mask[x, y] > 0.05 {
                    let px = rect.origin.x + CGFloat(x) * scaleX
                    let py = rect.origin.y + CGFloat(y) * scaleY
                    path.addRect(CGRect(x: px, y: py, width: scaleX, height: scaleY))
                }
            }
        }
        return path
    }

    /// Computes the largest aspect-preserving rect for the image inside `size`.
    private func fittedRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else {
            return .zero
        }
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = size.width / size.height
        let drawSize: CGSize
        if viewAspect > imageAspect {
            drawSize = CGSize(width: size.height * imageAspect, height: size.height)
        } else {
            drawSize = CGSize(width: size.width, height: size.width / imageAspect)
        }
        let origin = CGPoint(x: (size.width - drawSize.width) / 2,
                             y: (size.height - drawSize.height) / 2)
        return CGRect(origin: origin, size: drawSize)
    }

    // MARK: - Gesture -> pixel mapping

    private func paintGesture(in size: CGSize, image: RGBA8Image) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard model.phase.allowsPainting, let doc = model.document else { return }
                let rect = fittedRect(imageSize: CGSize(width: image.width, height: image.height), in: size)
                let pixel = value.location.toPixel(
                    displayedRect: rect,
                    imageWidth: doc.sourceSize.width,
                    imageHeight: doc.sourceSize.height
                )
                painter.paintDab(at: pixel.x, pixel.y, mode: mode)
            }
    }
}

// MARK: - Helpers

extension ResizePhase {
    /// Painting is only allowed when a document is ready and no resize is in flight.
    fileprivate var allowsPainting: Bool {
        switch self {
        case .ready, .cancelled, .completed:
            return true
        case .idle, .importing, .failed, .detectingFaces, .resizing:
            return false
        }
    }
}

extension AppModel {
    /// Convenience for the canvas: the working image when completed, else nil.
    fileprivate var workingImageOrNil: RGBA8Image? {
        if case .completed = phase { return document?.workingImage }
        return nil
    }
}

private extension CGPoint {
    /// Maps a view-space point into canonical image-pixel coordinates using the
    /// currently displayed image rect. Returns clamped integer pixel coords.
    func toPixel(displayedRect: CGRect, imageWidth: Int, imageHeight: Int) -> (x: Int, y: Int) {
        guard displayedRect.width > 0, displayedRect.height > 0, imageWidth > 0, imageHeight > 0 else {
            return (0, 0)
        }
        let nx = (x - displayedRect.origin.x) / displayedRect.width
        let ny = (y - displayedRect.origin.y) / displayedRect.height
        // Normalize into 0...1 within the displayed image, then scale to pixels.
        let clampedX = min(max(nx, 0), 1)
        let clampedY = min(max(ny, 0), 1)
        let px = Int((clampedX * CGFloat(imageWidth)).rounded())
        let py = Int((clampedY * CGFloat(imageHeight)).rounded())
        return (min(px, imageWidth - 1), min(py, imageHeight - 1))
    }
}
