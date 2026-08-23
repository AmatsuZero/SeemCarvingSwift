import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct SeamCarvingApp: App {
    var body: some Scene {
        WindowGroup("Seam Carving") {
            ContentView()
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        #endif
    }
}
