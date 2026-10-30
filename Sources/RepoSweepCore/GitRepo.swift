import Foundation

/// Receives progress lines as an operation runs. Main-actor bound so the UI
/// can append to its log directly, and awaited so lines arrive in order.
public typealias Logger = @MainActor @Sendable (String) -> Void

public struct GitHubRepo: Sendable, Hashable {
    public let owner: String
    public let name: String

    public var slug: String { "\(owner)/\(name)" }
    public var url: URL { URL(string: "https://github.com/\(owner)/\(name)")! }

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parses the remote URL forms git accepts for a GitHub repository:
    /// `git@github.com:o/r.git`, `ssh://git@github.com/o/r`,
    /// `https://github.com/o/r.git`, and SSH host aliases such as
    /// `github-work:o/r` that people set up for multiple accounts.
    public init?(remoteURL raw: String) {
        var rest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        if let schemeRange = rest.range(of: "://") {
            rest = String(rest[schemeRange.upperBound...])
            if let at = rest.firstIndex(of: "@"), at < (rest.firstIndex(of: "/") ?? rest.endIndex) {
                rest = String(rest[rest.index(after: at)...])
            }
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            host = String(rest[..<slash]).split(separator: ":").first.map(String.init) ?? ""
            rest = String(rest[rest.index(after: slash)...])
        } else if let colon = rest.firstIndex(of: ":") {
            var hostPart = String(rest[..<colon])
            if let at = hostPart.firstIndex(of: "@") {
                hostPart = String(hostPart[hostPart.index(after: at)...])
            }
            host = hostPart
            rest = String(rest[rest.index(after: colon)...])
        } else {
            return nil
        }
        guard host.lowercased().contains("github") else { return nil }

        if rest.hasSuffix("/") { rest.removeLast() }
        if rest.hasSuffix(".git") { rest.removeLast(4) }
        let parts = rest.split(separator: "/")
        guard parts.count == 2 else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }
}

/// What `git status` says about a checkout, for the repository header.
public struct LocalStatus: Sendable, Equatable {
    public var branch: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var dirty = false

    public init() {}
}

/// Git operations on one checkout. Every method is safe to call off the main
/// actor; the actual work happens in child processes.
public struct GitRepo: Sendable, Hashable {
    public let path: URL

    public init(path: URL) {
        self.path = path
    }

    @discardableResult
    func git(_ args: String...) async -> ShellResult {
        await git(args)
    }

    @discardableResult
    func git(_ args: [String], stdin: String? = nil) async -> ShellResult {
        await Shell.run(Shell.gitPath ?? "git", args, cwd: path, stdin: stdin)
    }

    /// Like `git(_:)`, but a non-zero exit throws with git's own message.
    @discardableResult
    func gitChecked(_ args: String...) async throws -> String {
        let result = await git(args)
        guard result.ok else {
            throw ShellError(message: "git \(args.joined(separator: " ")) failed: \(result.err)")
        }
        return result.out
    }

    public func gitHubRepo() async -> GitHubRepo? {
        let result = await git("remote", "get-url", "origin")
        guard result.ok else { return nil }
        return GitHubRepo(remoteURL: result.out)
    }

    public func defaultBranch() async -> String {
        let result = await git("symbolic-ref", "--short", "refs/remotes/origin/HEAD")
        if result.ok, let slash = result.out.firstIndex(of: "/") {
            return String(result.out[result.out.index(after: slash)...])
        }
        return "main"
    }

    public func currentBranch() async -> String? {
        let result = await git("branch", "--show-current")
        return result.ok && !result.out.isEmpty ? result.out : nil
    }

    public func isDirty() async -> Bool {
        // Untracked files count: `git switch` and `reset` can clobber them too.
        !(await git("status", "--porcelain").out.isEmpty)
    }

    public func status() async -> LocalStatus {
        var status = LocalStatus()
        let result = await git("status", "--porcelain=v2", "--branch")
        guard result.ok else { return status }
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 {
                    status.ahead = Int(parts[0].dropFirst()) ?? 0
                    status.behind = Int(parts[1].dropFirst()) ?? 0
                }
            } else if !line.hasPrefix("#") {
                status.dirty = true
            }
        }
        return status
    }

    /// `git fetch --prune`, tried again when another git is writing the same
    /// remote-tracking refs. An IDE or another app fetching in the background
    /// -- most likely right after a merge, when everything fetches -- makes
    /// ours fail with "cannot lock ref": it found the ref locked, or moved
    /// between reading and writing it. Waiting for the other fetch to finish
    /// and fetching again is all it takes.
    func fetchPrune(log: Logger, attempts: Int = 3, retryDelay: Duration = .seconds(1)) async throws {
        for attempt in 1...attempts {
            let fetch = await git("fetch", "--prune")
            if fetch.ok { return }
            guard attempt < attempts, fetch.stderr.contains("cannot lock ref") else {
                throw ShellError(message: "git fetch --prune failed: \(fetch.err)")
            }
            await log("another git is updating origin's refs, fetching again")
            try await Task.sleep(for: retryDelay * attempt)
        }
    }

    /// `git fetch --prune`, then a fast-forward-only pull of the checked-out
    /// branch. Fast-forward only, so an update never invents a merge commit
    /// or stops halfway through a rebase in a repository nobody is looking at.
    public func update(log: Logger) async throws {
        try await fetchPrune(log: log)
        await log("fetched")

        guard let branch = await currentBranch() else {
            await log("detached HEAD, nothing to pull")
            return
        }
        let upstream = await git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        guard upstream.ok else {
            await log("\(branch) has no upstream, nothing to pull")
            return
        }
        guard await git("rev-parse", "--verify", "--quiet", "@{u}").ok else {
            await log("\(branch): upstream \(upstream.out) is gone, nothing to pull")
            return
        }

        let pull = await git("pull", "--ff-only")
        guard pull.ok else {
            throw ShellError(message: "pull \(branch) failed: \(pull.err)")
        }
        let summary = pull.out.split(separator: "\n").first.map(String.init) ?? ""
        await log("pulled \(branch)\(summary.isEmpty ? "" : ": \(summary)")")
    }
}
