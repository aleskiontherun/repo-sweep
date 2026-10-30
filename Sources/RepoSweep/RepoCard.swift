import AppKit
import RepoSweepCore
import SwiftUI

struct RepoCard: View {
    @Environment(Workspace.self) private var model
    let repo: RepoState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(12)
            if repo.github != nil {
                Divider()
                pullRequests
                    .padding(.vertical, 6)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([repo.git.path])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repo.git.path.path, forType: .string)
            }
            if let github = repo.github {
                Button("Open on GitHub") { NSWorkspace.shared.open(github.url) }
            }
            Divider()
            Button(pinned ? "Unpin" : "Pin to Top", action: togglePin)
        }
    }

    private var pinned: Bool { Pins.shared.isPinned(repo.git.path) }

    private func togglePin() {
        withAnimation(.snappy) { Pins.shared.toggle(repo.git.path) }
    }

    private var pinButton: some View {
        Button(action: togglePin) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .rotationEffect(.degrees(45))
                .foregroundStyle(pinned ? Color.orange : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(pinned ? "Unpin" : "Pin to the top")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(repo.name)
                        .font(.headline)
                    if let github = repo.github {
                        Link(destination: github.url) {
                            Label(github.slug, systemImage: "arrow.up.right.square")
                                .labelStyle(.titleAndIcon)
                                .font(.callout)
                        }
                        .help(github.url.absoluteString)
                    } else {
                        Text("no GitHub remote")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
                branchLine
            }
            Spacer()
            if let activity = repo.activity {
                ProgressView().controlSize(.small)
                Text(activity).font(.callout).foregroundStyle(.secondary)
            } else if let result = repo.result {
                Text(result.text)
                    .font(.callout)
                    .foregroundStyle(result.isError ? .red : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(result.text)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            Group {
                Button("Update") { Task { await model.update(repo) } }
                    .help("Fetch with prune, pull, and reload pull requests")
                Button("Cleanup") { Task { await model.cleanup(repo) } }
                    .help(model.dryRun ? "Report merged branches without deleting them"
                                       : "Delete local branches that were merged")
            }
            .disabled(repo.activity != nil)
            pinButton
        }
    }

    private var branchLine: some View {
        HStack(spacing: 8) {
            let status = repo.status
            Label(status.branch ?? "detached HEAD", systemImage: "arrow.triangle.branch")
            if status.ahead > 0 { Text("↑\(status.ahead)").help("\(status.ahead) commits to push") }
            if status.behind > 0 { Text("↓\(status.behind)").help("\(status.behind) commits to pull") }
            if status.dirty {
                Text("modified").foregroundStyle(.orange).help("The checkout has uncommitted changes")
            }
            if let size = repo.size {
                Label(size.formatted(.byteCount(style: .file)), systemImage: "folder")
                    .help("Space the repository takes up on disk")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var pullRequests: some View {
        if let error = repo.prError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        } else if repo.pullRequests.isEmpty {
            HStack(spacing: 6) {
                if repo.loadingPRs {
                    ProgressView().controlSize(.mini)
                    Text("Loading pull requests…")
                } else {
                    Text("No open pull requests")
                }
            }
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(repo.pullRequests) { pr in
                    PRRow(pr: pr)
                }
            }
        }
    }
}
