import AppKit
import Foundation

/// Small AppKit adapters kept outside the shared editor so the same model and
/// views can be used by the iOS target.
@MainActor
enum MacPlatformServices {
    static func openImage() -> ImageSource? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return nil }
        return .nsImage(image)
    }

    static func savePNG(_ data: Data, suggestedName: String = "seam-carved.png") -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
