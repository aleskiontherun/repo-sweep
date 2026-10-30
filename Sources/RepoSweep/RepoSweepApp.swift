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
            }
            // Replaces the stock Close (⌘W), so ⌘W closes a tab first and
            // only the last tab closes the window, as in a browser.
            CommandGroup(replacing: .saveItem) {
                Button(tabs.workspaces.count > 1 ? "Close Tab" : "Close Window") {
                    if tabs.workspaces.count > 1 {
                        tabs.close(tabs.selected)
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut("w")
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandMenu("Repositories") {
                let workspace = tabs.selected
                Button("Update All") { Task { await workspace.updateAll() } }
                    .keyboardShortcut("r")
                Button("Cleanup All") { Task { await workspace.cleanupAll() } }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Rescan Without Fetching") { Task { await workspace.scan() } }
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
