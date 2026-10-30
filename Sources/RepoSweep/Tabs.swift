import Foundation
import Observation
import SwiftUI

/// The open tabs, saved to user defaults whenever a tab is opened, closed,
/// selected, or pointed at a different folder.
@MainActor @Observable
final class Tabs {
    private static let tabsKey = "tabs"
    private static let selectedKey = "selectedTab"
    /// Where the single working directory was kept before there were tabs.
    private static let legacyRootKey = "workingDirectory"

    private(set) var workspaces: [Workspace] = []
    var selectedID: UUID {
        didSet { save() }
    }

    var selected: Workspace {
        workspaces.first { $0.id == selectedID } ?? workspaces[0]
    }

    init() {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Self.tabsKey)
            ?? defaults.string(forKey: Self.legacyRootKey).map { [$0] }
            ?? []
        var workspaces = paths.map { path in
            // A folder that has since been moved or deleted reopens as a
            // clean tab rather than disappearing along with its position.
            Workspace(root: !path.isEmpty && FileManager.default.fileExists(atPath: path)
                      ? URL(fileURLWithPath: path) : nil)
        }
        if workspaces.isEmpty {
            workspaces = [Workspace()]
        }
        let index = min(max(defaults.integer(forKey: Self.selectedKey), 0), workspaces.count - 1)
        selectedID = workspaces[index].id
        self.workspaces = workspaces
        workspaces.forEach(observe)
    }

    func newTab() {
        let workspace = Workspace()
        observe(workspace)
        let index = workspaces.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? workspaces.endIndex
        workspaces.insert(workspace, at: index)
        selectedID = workspace.id
    }

    func close(_ workspace: Workspace) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces.remove(at: index)
        if selectedID == workspace.id {
            selectedID = workspaces[min(index, workspaces.count - 1)].id
        } else {
            save()
        }
    }

    func selectNext(_ offset: Int) {
        guard let index = workspaces.firstIndex(where: { $0.id == selectedID }) else { return }
        let count = workspaces.count
        selectedID = workspaces[((index + offset) % count + count) % count].id
    }

    private func observe(_ workspace: Workspace) {
        workspace.onRootChange = { [weak self] in self?.save() }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(workspaces.map { $0.root?.path ?? "" }, forKey: Self.tabsKey)
        defaults.set(workspaces.firstIndex { $0.id == selectedID } ?? 0, forKey: Self.selectedKey)
    }
}

struct TabBar: View {
    @Environment(Tabs.self) private var tabs

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.workspaces) { workspace in
                TabButton(workspace: workspace, selected: workspace.id == tabs.selectedID)
                if workspace.id != tabs.workspaces.last?.id {
                    Divider().padding(.vertical, 6)
                }
            }
        }
        .frame(height: 28)
        .background(.bar)
    }
}

private struct TabButton: View {
    @Environment(Tabs.self) private var tabs
    let workspace: Workspace
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            Text(workspace.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 24)
                .foregroundStyle(selected ? .primary : .secondary)
            HStack {
                Button {
                    tabs.close(workspace)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close Tab")
                .opacity(hovering ? 1 : 0)
                Spacer()
                if workspace.bulkActivity != nil || workspace.scanning {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 6)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .contentShape(Rectangle())
        .onTapGesture { tabs.selectedID = workspace.id }
        .onHover { hovering = $0 }
        .help(workspace.root?.path ?? "No working directory selected")
    }
}
