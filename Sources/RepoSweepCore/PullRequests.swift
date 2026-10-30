import Foundation

public struct PullRequest: Sendable, Identifiable, Decodable, Equatable {
    public struct Author: Sendable, Decodable, Equatable {
        public let login: String
    }

    /// One entry of `statusCheckRollup`: a `CheckRun` (Actions and other
    /// check suites) carries status/conclusion, a `StatusContext` (the older
    /// commit-status API) carries state.
    public struct Check: Sendable, Decodable, Equatable {
        public let status: String?
        public let conclusion: String?
        public let state: String?
    }

    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let author: Author?
    public let headRefName: String
    public let reviewDecision: String?
    public let mergeable: String?
    public let updatedAt: Date
    public let statusCheckRollup: [Check]?

    public var id: Int { number }

    public enum Checks: Sendable {
        case none, passing, pending, failing
    }

    public var checks: Checks {
        let rollup = statusCheckRollup ?? []
        guard !rollup.isEmpty else { return .none }
        var pending = false
        for check in rollup {
            switch check.result {
            case .failing: return .failing
            case .pending: pending = true
            default: break
            }
        }
        return pending ? .pending : .passing
    }

    public enum Review: Sendable {
        case none, approved, changesRequested, required
    }

    public var review: Review {
        switch reviewDecision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .required
        default: .none
        }
    }

    public var hasConflicts: Bool { mergeable == "CONFLICTING" }
}

extension PullRequest.Check {
    var result: PullRequest.Checks {
        if let state {
            switch state {
            case "SUCCESS": return .passing
            case "PENDING", "EXPECTED": return .pending
            default: return .failing
            }
        }
        guard status == "COMPLETED" else { return .pending }
        switch conclusion {
        case "SUCCESS", "NEUTRAL", "SKIPPED": return .passing
        default: return .failing
        }
    }
}

public enum PullRequests {
    static let fields = [
        "number", "title", "url", "isDraft", "author", "headRefName",
        "reviewDecision", "mergeable", "updatedAt", "statusCheckRollup",
    ]

    /// Runs `gh`, at most a few at a time and retrying failures with backoff.
    /// GitHub's GraphQL endpoint (or a VPN in front of it) drops bursts of
    /// parallel requests with `HTTP 499` or `unexpected EOF`, and a sweep of
    /// a workspace is exactly such a burst.
    static func gh(_ args: [String], cwd: URL) async -> ShellResult {
        await ghGate.acquire()
        var result = await Shell.run(Shell.ghPath ?? "gh", args, cwd: cwd)
        for delay in [1, 3] where !result.ok {
            try? await Task.sleep(for: .seconds(delay))
            result = await Shell.run(Shell.ghPath ?? "gh", args, cwd: cwd)
        }
        await ghGate.release()
        return result
    }

    static let ghGate = AsyncGate(limit: 3)

    public static func open(in repo: GitHubRepo, cwd: URL) async throws -> [PullRequest] {
        let result = await gh([
            "pr", "list", "--repo", repo.slug, "--state", "open", "--limit", "100",
            "--json", fields.joined(separator: ","),
        ], cwd: cwd)
        guard result.ok else {
            throw ShellError(message: result.err.isEmpty ? "gh pr list failed" : result.err)
        }
        return try decode(result.stdout)
    }

    public static func decode(_ json: String) throws -> [PullRequest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PullRequest].self, from: Data(json.utf8))
    }

    public enum BranchState: Sendable {
        case merged, open, none
    }

    /// Whether a branch's PR was merged, is still open, or never existed.
    /// An open PR wins over an older merged one for the same head: the branch
    /// is still in use.
    public static func state(ofBranch branch: String, in repo: GitHubRepo, cwd: URL) async throws -> BranchState {
        let result = await gh([
            "pr", "list", "--repo", repo.slug, "--head", branch, "--state", "all",
            "--json", "state",
        ], cwd: cwd)
        guard result.ok else {
            throw ShellError(message: "gh pr list for \(branch) failed: \(result.err)")
        }
        struct Entry: Decodable { let state: String }
        let states = try JSONDecoder().decode([Entry].self, from: Data(result.stdout.utf8)).map(\.state)
        if states.contains("OPEN") { return .open }
        if states.contains("MERGED") { return .merged }
        return .none
    }
}

/// A counting semaphore for async code.
actor AsyncGate {
    private let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            inUse -= 1
        } else {
            // Hand the slot straight to the next waiter.
            waiters.removeFirst().resume()
        }
    }
}
