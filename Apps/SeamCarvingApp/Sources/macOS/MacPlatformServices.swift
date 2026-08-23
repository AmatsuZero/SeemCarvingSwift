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

    static func save(_ data: Data, format: ExportFormat, suggestedName: String? = nil) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .png ? [.png] : [.jpeg]
        panel.nameFieldStringValue = suggestedName ?? "seam-carved.\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
