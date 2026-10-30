import RepoSweepCore
import SwiftUI

/// The window: a tab bar when there is more than one tab, the selected
/// tab's workspace, and the toolbar shared by all of them.
struct ContentView: View {
    @Environment(Tabs.self) private var tabs
    @AppStorage("showLog") private var showLog = true

    var body: some View {
        let workspace = tabs.selected
        VStack(spacing: 0) {
            TabBar()
            Divider()
            WorkspaceView(showLog: showLog)
                .environment(workspace)
                .id(workspace.id)
        }
        .navigationTitle(workspace.root.map { "RepoSweep — \($0.lastPathComponent)" } ?? "RepoSweep")
        .toolbar {
            ToolbarItem {
                Button {
                    showLog.toggle()
                } label: {
                    Label(showLog ? "Hide Log" : "Show Log", systemImage: "text.alignleft")
                }
                .help(showLog ? "Hide the log" : "Show the log")
            }
        }
    }
}

struct WorkspaceView: View {
    @Environment(Workspace.self) private var model
    let showLog: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            directoryBar
            Divider()
            actionBar(dryRun: $model.dryRun)
            Divider()
            repositoryList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showLog {
                Divider()
                LogPane()
                    .frame(height: 180)
            }
            if model.root != nil {
                Divider()
                statusBar
            }
        }
        .task {
            if !model.scanned { await model.scan() }
        }
    }

    private var directoryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            if let root = model.root {
                Text(root.path)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            } else {
                Text("No working directory selected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.root == nil ? "Select Working Directory…" : "Change…") {
                model.chooseRoot()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func actionBar(dryRun: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.updateAll() }
            } label: {
                Label("Update all", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Rescan the folder, fetch with prune and pull every repository, then reload pull requests (⌘R)")

            Button {
                Task { await model.cleanupAll() }
            } label: {
                Label("Cleanup all", systemImage: "sparkles")
            }
            .help("Delete local branches that were merged, in every repository (⇧⌘K)")

            Toggle("Dry run", isOn: dryRun)
                .toggleStyle(.checkbox)
                .help("Report what cleanup would delete without deleting anything")

            Spacer()

            if let activity = model.bulkActivity ?? (model.scanning ? "Scanning…" : nil) {
                ProgressView().controlSize(.small)
                Text(activity).foregroundStyle(.secondary)
            } else if model.root != nil {
                Text("^[\(model.repos.count) repository](inflect: true)")
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await model.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan the folder and reload pull requests without fetching")
        }
        .disabled(model.root == nil || model.bulkActivity != nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// The working directory's size on disk and the free space left on its
    /// volume, refreshed after each scan, update and cleanup.
    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            if let size = model.directorySize {
                Text(size, format: .byteCount(style: .file))
            } else {
                Text("measuring…")
            }
            if model.measuringSize && model.directorySize != nil {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            if let free = model.freeSpace {
                Image(systemName: "internaldrive")
                Text("\(free, format: .byteCount(style: .file)) free")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .help("Space the working directory takes up on disk, and free space on its volume")
    }

    @ViewBuilder
    private var repositoryList: some View {
        if !model.missingTools.isEmpty {
            ContentUnavailableView(
                "Missing \(model.missingTools.joined(separator: " and "))",
                systemImage: "exclamationmark.triangle",
                description: Text("Install it (for example with Homebrew) and relaunch RepoSweep.")
            )
        } else if model.root == nil {
            ContentUnavailableView {
                Label("Select a working directory", systemImage: "folder.badge.questionmark")
            } description: {
                Text("RepoSweep lists every git repository under it.")
            } actions: {
                Button("Select…") { model.chooseRoot() }
            }
        } else if model.repos.isEmpty && !model.scanning {
            ContentUnavailableView("No repositories", systemImage: "tray",
                                   description: Text("No git repositories were found under this folder."))
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.orderedRepos) { repo in
                        RepoCard(repo: repo)
                    }
                }
                .padding(16)
            }
        }
    }
}
