import AppKit
import SwiftUI

@main
struct RepoSweepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var tabs = Tabs()

    var body: some Scene {
        Window("RepoSweep", id: "main") {
            ContentView()
                .environment(tabs)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 900, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { tabs.newTab() }
                    .keyboardShortcut("t")
                Button("Close Tab") { tabs.close(tabs.selected) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(tabs.workspaces.count < 2)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Show Previous Tab") { tabs.selectNext(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Show Next Tab") { tabs.selectNext(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (`swift run`) rather than
        // from the .app bundle, which would otherwise get no Dock icon or
        // keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
