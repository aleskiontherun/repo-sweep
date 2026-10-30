import RepoSweepCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showLog = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            directoryBar
            Divider()
            actionBar(dryRun: $model.dryRun)
            Divider()
            repositoryList
            if showLog {
                Divider()
                LogPane()
                    .frame(height: 180)
            }
        }
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
        .task { await model.scan() }
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
            .help("Fetch with prune and pull every repository, then reload pull requests")

            Button {
                Task { await model.cleanupAll() }
            } label: {
                Label("Cleanup all", systemImage: "scissors")
            }
            .help("Delete local branches that were merged, in every repository")

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
                    ForEach(model.repos) { repo in
                        RepoCard(repo: repo)
                    }
                }
                .padding(16)
            }
        }
    }
}
