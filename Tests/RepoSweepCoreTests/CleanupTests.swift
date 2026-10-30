import Foundation
import Testing
@testable import RepoSweepCore

/// A clone of a local bare "origin", with branches merged every way GitHub
/// merges them and then deleted from the remote, as a merged PR leaves them.
struct Fixture {
    let dir: URL
    let origin: URL
    let clone: URL

    var repo: GitRepo { GitRepo(path: clone) }

    init() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-sweep-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        origin = dir.appendingPathComponent("origin.git")
        clone = dir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try await sh(dir, "init", "-q", "--bare", "-b", "main", origin.path)
        try await sh(dir, "clone", "-q", origin.path, clone.path)
        try await git("config", "user.email", "test@example.com")
        try await git("config", "user.name", "Test")
        try await commit("README", "hello")
        try await git("push", "-q", "-u", "origin", "main")
        try await git("remote", "set-head", "origin", "main")
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    func git(_ args: String...) async throws -> String {
        try await sh(clone, args)
    }

    @discardableResult
    func sh(_ cwd: URL, _ args: String...) async throws -> String {
        try await sh(cwd, args)
    }

    @discardableResult
    func sh(_ cwd: URL, _ args: [String]) async throws -> String {
        let result = await Shell.run("git", args, cwd: cwd)
        guard result.ok else { throw ShellError(message: "git \(args.joined(separator: " ")): \(result.err)") }
        return result.out
    }

    func commit(_ file: String, _ content: String) async throws {
        try content.write(to: clone.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try await git("add", file)
        try await git("commit", "-q", "-m", "\(file): \(content)")
    }

    /// A pushed branch with one commit on it, then back on main.
    func branch(_ name: String, file: String) async throws {
        try await git("switch", "-q", "-c", name, "main")
        try await commit(file, name)
        try await git("push", "-q", "-u", "origin", name)
        try await git("switch", "-q", "main")
    }

    func deleteRemote(_ name: String) async throws {
        try await git("push", "-q", "origin", "--delete", name)
    }

    func branches() async throws -> Set<String> {
        Set(try await git("for-each-ref", "refs/heads", "--format=%(refname:short)").split(separator: "\n").map(String.init))
    }
}

@MainActor
final class LogSink {
    var lines: [String] = []
    var logger: Logger { { [weak self] in self?.lines.append($0) } }
}

@Suite(.serialized) struct CleanupTests {
    @Test func deletesOnlyBranchesThatLanded() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        // Rebased/fast-forwarded into main, no PR.
        try await f.branch("ff", file: "ff")
        try await f.git("merge", "-q", "--ff-only", "ff")
        // Squash-merged, no PR.
        try await f.branch("squashed", file: "squashed")
        try await f.git("merge", "-q", "--squash", "squashed")
        try await f.git("commit", "-q", "-m", "squash")
        // Abandoned: never merged, no PR.
        try await f.branch("abandoned", file: "abandoned")
        // GitHub says merged, though main doesn't hold it (say, a merge to
        // another base): the PR is the authority.
        try await f.branch("pr-merged", file: "pr-merged")
        // Stacked PR still open.
        try await f.branch("pr-open", file: "pr-open")
        // Not gone at all: its remote branch is still there.
        try await f.branch("alive", file: "alive")

        try await f.git("push", "-q", "origin", "main")
        for name in ["ff", "squashed", "abandoned", "pr-merged", "pr-open"] {
            try await f.deleteRemote(name)
        }

        let lookup: Cleanup.PRLookup = { branch in
            switch branch {
            case "pr-merged": .merged
            case "pr-open": .open
            default: .none
            }
        }

        let sink = await LogSink()
        try await Cleanup(repo: f.repo, dryRun: true, lookup: lookup).run(log: sink.logger)
        #expect(try await f.branches() == ["main", "ff", "squashed", "abandoned", "pr-merged", "pr-open", "alive"])

        try await Cleanup(repo: f.repo, dryRun: false, lookup: lookup).run(log: sink.logger)
        #expect(try await f.branches() == ["main", "abandoned", "pr-open", "alive"])
    }

    @Test func leavesMergedCheckedOutBranchForUpdatedMain() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.branch("feature", file: "feature")
        // Someone merges the PR on GitHub (squash) and deletes the branch.
        let other = f.dir.appendingPathComponent("other")
        try await f.sh(f.dir, "clone", "-q", f.origin.path, other.path)
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "merge", "-q", "--squash", "origin/feature")
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "-m", "Feature (#1)")
        try await f.sh(other, "push", "-q", "origin", "main")
        try await f.deleteRemote("feature")

        try await f.git("switch", "-q", "feature")
        let sink = await LogSink()
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)

        #expect(try await f.git("branch", "--show-current") == "main")
        #expect(try await f.branches() == ["main"])
        #expect(try await f.git("rev-parse", "main") == (try await f.git("rev-parse", "origin/main")))
    }

    @Test func leavesMergedCheckedOutBranchWhoseRemoteBranchIsStillThere() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.branch("feature", file: "feature")
        // Squash-merged into main, but its branch isn't deleted. No PR either:
        // what main holds is what counts.
        let other = f.dir.appendingPathComponent("other")
        try await f.sh(f.dir, "clone", "-q", f.origin.path, other.path)
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "merge", "-q", "--squash", "origin/feature")
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "-m", "Feature (#1)")
        try await f.sh(other, "push", "-q", "origin", "main")

        try await f.git("switch", "-q", "feature")
        let sink = await LogSink()
        try await Cleanup(repo: f.repo, dryRun: true, lookup: { _ in .none }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "feature")

        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .none }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "main")
        #expect(try await f.branches() == ["main"])
        #expect(try await f.git("rev-parse", "main") == (try await f.git("rev-parse", "origin/main")))
    }

    @Test func leavesCheckedOutBranchWhosePRMergedWithMergeCommit() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.branch("feature", file: "feature")
        try await f.git("merge", "-q", "--no-ff", "-m", "Merge #1", "feature")
        try await f.git("push", "-q", "origin", "main")
        try await f.git("switch", "-q", "feature")

        let sink = await LogSink()
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .none }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "feature")

        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "main")
        #expect(try await f.branches() == ["main"])
    }

    @Test func keepsCheckedOutBranchThatIsNotMerged() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }
        let sink = await LogSink()

        // Just cut from main, under the name of an older branch whose PR was
        // merged.
        try await f.git("switch", "-q", "-c", "fresh")
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "fresh")
        try await f.git("switch", "-q", "main")
        try await f.git("branch", "-q", "-D", "fresh")

        // Just cut from main, and main has moved on since: by content it's
        // already in main.
        try await f.git("switch", "-q", "-c", "fresh")
        let other = f.dir.appendingPathComponent("other")
        try await f.sh(f.dir, "clone", "-q", f.origin.path, other.path)
        try "new".write(to: other.appendingPathComponent("new"), atomically: true, encoding: .utf8)
        try await f.sh(other, "add", "new")
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "-m", "new")
        try await f.sh(other, "push", "-q", "origin", "main")
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .none }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "fresh")

        // Merged, but with more work committed since.
        try await f.git("switch", "-q", "main")
        try await f.git("merge", "-q", "--ff-only", "origin/main")
        try await f.branch("feature", file: "feature")
        try await f.git("merge", "-q", "--no-ff", "-m", "Merge #1", "feature")
        try await f.git("push", "-q", "origin", "main")
        try await f.git("switch", "-q", "feature")
        try await f.commit("more", "more")
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "feature")

        // Merged, and its PR is open again for a follow-up.
        try await f.git("reset", "-q", "--hard", "HEAD~1")
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .open }).run(log: sink.logger)
        #expect(try await f.git("branch", "--show-current") == "feature")
        #expect(try await f.branches() == ["main", "fresh", "feature"])
    }

    @Test func keepsCheckedOutBranchWithLocalChanges() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.branch("feature", file: "feature")
        try await f.deleteRemote("feature")
        try await f.git("switch", "-q", "feature")
        try "wip".write(to: f.clone.appendingPathComponent("wip"), atomically: true, encoding: .utf8)

        let sink = await LogSink()
        try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)

        #expect(try await f.git("branch", "--show-current") == "feature")
        #expect(try await f.branches().contains("feature"))
    }

    @Test func removesCleanWorktreeOfMergedBranchButNotDirtyOne() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.branch("clean", file: "clean")
        try await f.branch("dirty", file: "dirty")
        try await f.deleteRemote("clean")
        try await f.deleteRemote("dirty")
        let cleanTree = f.dir.appendingPathComponent("wt-clean")
        let dirtyTree = f.dir.appendingPathComponent("wt-dirty")
        try await f.git("worktree", "add", "-q", cleanTree.path, "clean")
        try await f.git("worktree", "add", "-q", dirtyTree.path, "dirty")
        try "wip".write(to: dirtyTree.appendingPathComponent("wip"), atomically: true, encoding: .utf8)
        let cleanSize = try #require(DiskUsage.allocatedSize(of: cleanTree))

        let sink = await LogSink()
        let freed = try await Cleanup(repo: f.repo, dryRun: false, lookup: { _ in .merged }).run(log: sink.logger)

        #expect(freed == cleanSize)
        #expect(!FileManager.default.fileExists(atPath: cleanTree.path))
        #expect(FileManager.default.fileExists(atPath: dirtyTree.path))
        #expect(try await f.branches() == ["main", "dirty"])
    }

    @Test func updatePullsFastForward() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        let other = f.dir.appendingPathComponent("other")
        try await f.sh(f.dir, "clone", "-q", f.origin.path, other.path)
        try "new".write(to: other.appendingPathComponent("new"), atomically: true, encoding: .utf8)
        try await f.sh(other, "add", "new")
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "-m", "new")
        try await f.sh(other, "push", "-q", "origin", "main")

        let sink = await LogSink()
        try await f.repo.update(log: sink.logger)
        #expect(FileManager.default.fileExists(atPath: f.clone.appendingPathComponent("new").path))
        #expect(await f.repo.status().behind == 0)
    }

    /// Another git fetching at the same moment -- an IDE, right after a merge
    /// -- holds the lock on `origin/main` that ours needs.
    @Test func fetchWaitsOutAnotherFetchHoldingTheRefLock() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        let other = f.dir.appendingPathComponent("other")
        try await f.sh(f.dir, "clone", "-q", f.origin.path, other.path)
        try await f.sh(other, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "--allow-empty", "-m", "merged")
        try await f.sh(other, "push", "-q", "origin", "main")

        let lock = f.clone.appendingPathComponent(".git/refs/remotes/origin/main.lock")
        try "".write(to: lock, atomically: false, encoding: .utf8)
        let sink = await LogSink()
        let record = await sink.logger
        // The other fetch finishes as ours backs off.
        let logger: Logger = { line in
            record(line)
            if line.contains("fetching again") { try? FileManager.default.removeItem(at: lock) }
        }
        try await Cleanup(repo: f.repo, dryRun: true, lookup: { _ in .none }).run(log: logger)
        #expect(await sink.lines.filter { $0.contains("fetching again") }.count == 1)
        #expect(try await f.git("rev-parse", "origin/main") == (try await f.sh(other, "rev-parse", "HEAD")))
    }

    @Test func fetchGivesUpOnARefLockThatStaysHeld() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        try await f.git("commit", "-q", "--allow-empty", "-m", "ahead")
        try await f.git("push", "-q", "origin", "main")
        try await f.git("update-ref", "refs/remotes/origin/main", "HEAD~1")
        try "".write(to: f.clone.appendingPathComponent(".git/refs/remotes/origin/main.lock"),
                     atomically: false, encoding: .utf8)

        let sink = await LogSink()
        await #expect(throws: ShellError.self) {
            try await f.repo.fetchPrune(log: sink.logger, retryDelay: .milliseconds(10))
        }
        #expect(await sink.lines.filter { $0.contains("fetching again") }.count == 2)
    }

    @Test func discoveryFindsNestedReposAndSkipsWorktrees() async throws {
        let f = try await Fixture()
        defer { f.cleanUp() }

        let nested = f.dir.appendingPathComponent("group/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try await f.sh(nested, "init", "-q")
        try await f.branch("wt", file: "wt")
        try await f.git("worktree", "add", "-q", f.dir.appendingPathComponent("worktree").path, "wt")

        let found = await Discovery.repositories(under: f.dir).map(\.lastPathComponent)
        #expect(found == ["nested", "work"])
    }
}
