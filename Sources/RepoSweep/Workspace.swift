import AppKit
import Observation
import RepoSweepCore

struct LogLine: Identifiable {
    let id = UUID()
    let date = Date()
    let repo: String?
    let text: String
    let isError: Bool
}

@MainActor @Observable
final class RepoState: Identifiable {
    let git: GitRepo
    let name: String
    var github: GitHubRepo?
    var status = LocalStatus()
    var pullRequests: [PullRequest] = []
    var prError: String?
    var loadingPRs = false
    /// What the repository is doing right now, shown next to its name.
    var activity: String?
    /// The outcome of the last update or cleanup.
    var result: (text: String, isError: Bool)?
    /// The repository's size on disk, nil until first measured.
    var size: Int64?

    nonisolated var id: URL { git.path }

    init(path: URL, name: String) {
        git = GitRepo(path: path)
        self.name = name
    }
}

/// One tab: a working directory and the repositories under it.
@MainActor @Observable
final class Workspace: Identifiable {
    /// How many repositories are fetched or cleaned at once.
    private static let concurrency = 6

    let id = UUID()
    var root: URL? {
        didSet { onRootChange?() }
    }
    var repos: [RepoState] = []
    /// `repos` as listed: pinned ones first, each group in path order.
    var orderedRepos: [RepoState] {
        let pins = Pins.shared
        return repos.filter { pins.isPinned($0.git.path) } + repos.filter { !pins.isPinned($0.git.path) }
    }
    var log: [LogLine] = []
    var scanning = false
    /// Set once the first scan has started, so switching back to a tab
    /// doesn't rescan it.
    var scanned = false
    var bulkActivity: String?
    var dryRun = false
    /// The working directory's size on disk, nil until first measured.
    var directorySize: Int64?
    /// Free space on the working directory's volume.
    var freeSpace: Int64?
    var measuringSize = false
    /// What the Cleanup all running now has freed so far.
    @ObservationIgnored private var freedByCleanupAll: Int64 = 0
    @ObservationIgnored private var measurement: Task<Void, Never>?
    @ObservationIgnored var onRootChange: (() -> Void)?

    var title: String { root?.lastPathComponent ?? "New Tab" }

    var missingTools: [String] {
        [("git", Shell.gitPath), ("gh", Shell.ghPath)].compactMap { $0.1 == nil ? $0.0 : nil }
    }

    init(root: URL? = nil) {
        self.root = root
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder containing git repositories"
        panel.directoryURL = root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url != root else { return }
        root = url
        repos = []
        directorySize = nil
        freeSpace = nil
        Task { await scan() }
    }

    // MARK: Scanning

    /// Rediscovers the repositories and reloads each one's status and pull
    /// requests, without fetching.
    func scan() async {
        guard await discover() else { return }
        measureDisk()
        await forEach(orderedRepos) { repo in
            await self.refreshLocal(repo)
            await self.refreshPRs(repo)
        }
    }

    /// Re-measures the working directory's size, each repository's share of
    /// it and the free space beside it, in one walk off the main actor. A
    /// measurement still running is cancelled, so the figures shown are
    /// always the latest root's.
    func measureDisk() {
        measurement?.cancel()
        guard let root else { return }
        let paths = repos.map(\.git.path)
        measuringSize = true
        measurement = Task {
            let walk = Task.detached(priority: .utility) {
                (DiskUsage.allocatedSizes(of: root, splitBy: paths), DiskUsage.freeSpace(at: root))
            }
            let measured = await withTaskCancellationHandler {
                await walk.value
            } onCancel: {
                walk.cancel()
            }
            guard !Task.isCancelled, root == self.root else { return }
            if let sizes = measured.0 {
                directorySize = sizes.total
                for repo in repos {
                    if let size = sizes.subdirs[repo.git.path] { repo.size = size }
                }
            }
            freeSpace = measured.1
            measuringSize = false
        }
    }

    /// Re-reads which repositories are under the root: ones added since the
    /// last look join the list, deleted ones leave it, and the rest keep
    /// their state. Returns false when there is no root, or another
    /// discovery is already running.
    @discardableResult
    func discover() async -> Bool {
        guard let root, !scanning else { return false }
        scanned = true
        scanning = true
        defer { scanning = false }

        let paths = await Discovery.repositories(under: root)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let hadList = !repos.isEmpty
        let existing = Dictionary(uniqueKeysWithValues: repos.map { ($0.git.path, $0) })
        let updated = paths.map { path in
            existing[path] ?? RepoState(path: path, name: label(for: path, under: root))
        }
        if hadList {
            let kept = Set(paths)
            for repo in updated where existing[repo.git.path] == nil {
                append(repo.name, "new repository")
            }
            for repo in repos where !kept.contains(repo.git.path) {
                append(repo.name, "repository no longer there, removed from the list")
            }
        }
        repos = updated
        return true
    }

    private func label(for path: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.path != rootPath else { return root.lastPathComponent }
        return path.path.hasPrefix(rootPath + "/") ? String(path.path.dropFirst(rootPath.count + 1)) : path.path
    }

    func refreshLocal(_ repo: RepoState) async {
        if repo.github == nil {
            repo.github = await repo.git.gitHubRepo()
        }
        repo.status = await repo.git.status()
    }

    func refreshPRs(_ repo: RepoState) async {
        guard let github = repo.github else {
            repo.pullRequests = []
            repo.prError = nil
            return
        }
        repo.loadingPRs = true
        defer { repo.loadingPRs = false }
        do {
            repo.pullRequests = try await PullRequests.open(in: github, cwd: repo.git.path)
            repo.prError = nil
        } catch {
            repo.prError = error.localizedDescription
            append(repo.name, "pull requests: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: Actions

    func updateAll() async {
        guard bulkActivity == nil else { return }
        bulkActivity = "Updating…"
        defer { bulkActivity = nil }
        // Let a discovery already in flight (the first one, on opening the
        // tab) finish, then look again so the list is current.
        while scanning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await discover()
        await forEach(orderedRepos) { await self.update($0) }
        append(nil, "Update all finished")
        measureDisk()
    }

    func cleanupAll() async {
        guard bulkActivity == nil else { return }
        bulkActivity = dryRun ? "Cleaning up (dry run)…" : "Cleaning up…"
        defer { bulkActivity = nil }
        freedByCleanupAll = 0
        await forEach(orderedRepos) { await self.cleanup($0) }
        append(nil, dryRun ? "Cleanup all finished (dry run, nothing deleted)"
                           : "Cleanup all finished, freed \(Self.bytes(freedByCleanupAll))")
        measureDisk()
    }

    func update(_ repo: RepoState) async {
        await perform("Updating…", on: repo) {
            try await repo.git.update(log: self.logger(for: repo))
            return "Updated"
        }
        await refreshPRs(repo)
        // A bulk action measures once, when it's done. The whole working
        // directory is walked again rather than just this repository: its
        // nested repositories and removed worktrees count elsewhere.
        if bulkActivity == nil { measureDisk() }
    }

    func cleanup(_ repo: RepoState) async {
        let dryRun = dryRun
        await perform(dryRun ? "Cleaning up (dry run)…" : "Cleaning up…", on: repo) {
            let freed = try await Cleanup(repo: repo.git, dryRun: dryRun).run(log: self.logger(for: repo))
            if dryRun { return "Cleanup dry run done" }
            self.freedByCleanupAll += freed
            // Cleanup all sums them up, so only the repositories that freed something get a line.
            if freed > 0 || self.bulkActivity == nil { self.append(repo.name, "freed \(Self.bytes(freed))") }
            return "Cleaned up, freed \(Self.bytes(freed))"
        }
        if bulkActivity == nil { measureDisk() }
    }

    /// Runs `body`, which returns the text to show when it succeeds.
    private func perform(_ activity: String, on repo: RepoState,
                         _ body: () async throws -> String) async {
        guard repo.activity == nil else { return }
        repo.activity = activity
        defer { repo.activity = nil }
        do {
            repo.result = (try await body(), false)
        } catch {
            repo.result = (error.localizedDescription, true)
            append(repo.name, error.localizedDescription, isError: true)
        }
        await refreshLocal(repo)
    }

    // MARK: Helpers

    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }

    private func logger(for repo: RepoState) -> Logger {
        let name = repo.name
        return { [weak self] line in
            self?.append(name, line, isError: line.hasPrefix("!") || line.contains(" ! "))
        }
    }

    func append(_ repo: String?, _ text: String, isError: Bool = false) {
        log.append(LogLine(repo: repo, text: text, isError: isError))
        if log.count > 5000 { log.removeFirst(log.count - 5000) }
    }

    func clearLog() { log.removeAll() }

    /// Runs `body` for each repository, a few at a time: enough to overlap
    /// network round-trips without starting a hundred `git fetch`es at once.
    private func forEach(_ items: [RepoState], _ body: @escaping @MainActor (RepoState) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<Self.concurrency {
                guard let item = iterator.next() else { break }
                group.addTask { await body(item) }
            }
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask { await body(item) }
                }
            }
        }
    }
}
