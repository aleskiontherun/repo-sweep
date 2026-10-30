import Foundation

/// Deletes local branches whose work has actually landed, and the worktrees
/// stranded behind them.
///
/// `[gone]` only means the remote branch was deleted -- not that it was
/// merged: it could have been abandoned, or be mid-flight in a stacked PR.
/// Squash-merged branches never show up in `git branch --merged` either. So
/// each `[gone]` branch is checked against GitHub, and deleted only when a PR
/// for it is MERGED. A branch with an OPEN PR is kept. A branch with no PR at
/// all is deleted only if `<base>` already contains its commits or an
/// equivalent squashed patch, and reported for manual review otherwise.
///
/// When the branch to delete is the one checked out in the main checkout,
/// the checkout is first switched to an up-to-date `<base>` -- provided it
/// has no local changes, which the switch could clobber.
///
/// Nothing is removed with `--force`: a worktree with uncommitted work, or a
/// locked one, is kept and named in the log, and so is its branch.
public struct Cleanup: Sendable {
    public typealias PRLookup = @Sendable (_ branch: String) async throws -> PullRequests.BranchState

    let repo: GitRepo
    let dryRun: Bool
    let lookup: PRLookup

    public init(repo: GitRepo, dryRun: Bool, lookup: PRLookup? = nil) {
        self.repo = repo
        self.dryRun = dryRun
        if let lookup {
            self.lookup = lookup
        } else {
            self.lookup = { branch in
                guard let gh = await repo.gitHubRepo() else { return .none }
                return try await PullRequests.state(ofBranch: branch, in: gh, cwd: repo.path)
            }
        }
    }

    public func run(log: Logger) async throws {
        try await repo.gitChecked("fetch", "--prune")
        let prune = await repo.git(dryRun ? ["worktree", "prune", "-n", "-v"] : ["worktree", "prune", "-v"])
        for line in (prune.stdout + prune.stderr).split(separator: "\n") {
            await log(String(line))
        }

        let base = await repo.defaultBranch()
        let baseRef = await repo.git("rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(base)").ok
            ? "origin/\(base)" : base
        let trees = try await linkedWorktrees()

        try await cleanBranches(base: base, baseRef: baseRef, trees: trees, log: log)
        await cleanDetachedWorktrees(baseRef: baseRef, trees: trees, log: log)
    }

    // MARK: Branches

    func goneBranches(excluding base: String) async throws -> [String] {
        let out = try await repo.gitChecked(
            "for-each-ref", "refs/heads", "--format=%(refname:short)|%(upstream:track)"
        )
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] != base, parts[1].contains("[gone]") else { return nil }
            return String(parts[0])
        }
    }

    enum Verdict {
        case delete(String)
        case keep(String)
    }

    func verdict(for branch: String, baseRef: String, log: Logger) async -> Verdict {
        do {
            switch try await lookup(branch) {
            case .merged: return .delete("PR merged")
            case .open: return .keep("PR still open")
            case .none: break
            }
        } catch {
            await log("! \(error.localizedDescription)")
            return .keep("couldn't check its PR")
        }
        if await repo.git("merge-base", "--is-ancestor", branch, baseRef).ok {
            return .delete("no PR, already in \(baseRef)")
        }
        if await isSquashMerged(branch, into: baseRef) {
            return .delete("no PR, an equal patch is in \(baseRef)")
        }
        return .keep("review manually: no PR, not merged into \(baseRef)")
    }

    /// A squash merge rewrites the branch as one new commit, so none of the
    /// branch's own commits are in base's history. Ask about content instead:
    /// collapse the branch into one commit off the merge base and let
    /// `git cherry` say whether base already holds an equal patch.
    func isSquashMerged(_ branch: String, into baseRef: String) async -> Bool {
        let mergeBase = await repo.git("merge-base", baseRef, branch)
        guard mergeBase.ok else { return false }
        let squashed = await repo.git("commit-tree", "\(branch)^{tree}", "-p", mergeBase.out, "-m", "_")
        guard squashed.ok else { return false }
        return await repo.git("cherry", baseRef, squashed.out).out.hasPrefix("-")
    }

    func cleanBranches(base: String, baseRef: String, trees: [Worktree], log: Logger) async throws {
        let candidates = try await goneBranches(excluding: base)
        guard !candidates.isEmpty else {
            await log("no [gone] branches")
            return
        }
        let current = await repo.currentBranch()
        let attached = Dictionary(trees.compactMap { tree in tree.branch.map { ($0, tree) } },
                                  uniquingKeysWith: { first, _ in first })

        for branch in candidates {
            let verdict = await verdict(for: branch, baseRef: baseRef, log: log)
            guard case .delete(let reason) = verdict else {
                if case .keep(let reason) = verdict { await log("\(branch): keep (\(reason))") }
                continue
            }
            let checkedOut = branch == current
            await log("\(branch): delete (\(reason))\(checkedOut ? ", checked out here" : "")\(dryRun ? " [dry run]" : "")")
            if dryRun { continue }

            if checkedOut {
                guard try await switchToBase(base, from: branch, log: log) else { continue }
            }
            if let tree = attached[branch], !(await remove(tree, reason: "branch deleted", log: log)) {
                // git won't drop a branch a worktree still has checked out.
                await log("  \(branch) kept too, its worktree still holds it")
                continue
            }
            try await repo.gitChecked("branch", "-D", branch)
            await log("  deleted \(branch)")
        }
    }

    /// Leaves `branch` for an up-to-date `base`, the way `git-main` does.
    /// Fast-forward only: unlike a hard reset, it can't drop local commits on
    /// base that were never pushed.
    func switchToBase(_ base: String, from branch: String, log: Logger) async throws -> Bool {
        if await repo.isDirty() {
            await log("  \(branch) kept: the checkout has local changes, commit or stash them first")
            return false
        }
        try await repo.gitChecked("switch", base)
        await log("  switched to \(base)")
        if await repo.git("rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(base)").ok {
            let merge = await repo.git("merge", "--ff-only", "origin/\(base)")
            await log(merge.ok ? "  updated \(base) to origin/\(base)"
                               : "  ! \(base) can't fast-forward to origin/\(base): \(merge.err)")
        }
        return true
    }

    // MARK: Worktrees

    struct Worktree: Sendable {
        var path: String
        var head: String?
        var branch: String?
        var detached = false
        var locked = false
    }

    /// Every worktree registration except the main checkout, which
    /// `git worktree remove` refuses anyway, and the repo path itself.
    func linkedWorktrees() async throws -> [Worktree] {
        var trees: [Worktree] = []
        var current: Worktree?
        for line in try await repo.gitChecked("worktree", "list", "--porcelain").split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            if line.isEmpty {
                if let tree = current { trees.append(tree) }
                current = nil
                continue
            }
            let parts = line.split(separator: " ", maxSplits: 1)
            let key = String(parts[0]), value = parts.count > 1 ? String(parts[1]) : ""
            switch key {
            case "worktree": current = Worktree(path: value)
            case "HEAD": current?.head = value
            case "branch": current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst(11)) : value
            case "detached": current?.detached = true
            case "locked": current?.locked = true
            default: break
            }
        }
        if let tree = current { trees.append(tree) }

        let resolved = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        var skip: Set<String> = [resolved(repo.path.path)]
        if let main = trees.first { skip.insert(resolved(main.path)) }
        return trees.filter { !skip.contains(resolved($0.path)) }
    }

    func remove(_ tree: Worktree, reason: String, log: Logger) async -> Bool {
        let path = tree.path
        guard FileManager.default.fileExists(atPath: path) else { return true }
        if tree.locked {
            await log("  worktree kept: \(path) (locked)")
            return false
        }
        if !(await Shell.run(Shell.gitPath ?? "git", ["status", "--porcelain"], cwd: URL(fileURLWithPath: path)).out.isEmpty) {
            await log("  worktree kept: \(path) (uncommitted work)")
            return false
        }
        let result = await repo.git("worktree", "remove", path)
        guard result.ok else {
            await log("  worktree kept: \(path) (\(result.err))")
            return false
        }
        await log("  worktree removed: \(path) (\(reason))")
        return true
    }

    /// Worktrees whose branch is already gone, left detached. Detached at a
    /// commit already in base means the work shipped; detached anywhere else
    /// means unmerged work nobody tracks any more -- reported, never removed.
    func cleanDetachedWorktrees(baseRef: String, trees: [Worktree], log: Logger) async {
        for tree in trees where tree.detached {
            guard FileManager.default.fileExists(atPath: tree.path) else { continue }
            let head = tree.head ?? ""
            let short = String(head.prefix(8))
            guard await repo.git("merge-base", "--is-ancestor", head, baseRef).ok else {
                await log("dangling worktree \(tree.path): review manually (detached at \(short), not in \(baseRef))")
                continue
            }
            await log("dangling worktree \(tree.path): remove (detached at \(short), already in \(baseRef))\(dryRun ? " [dry run]" : "")")
            if !dryRun {
                _ = await remove(tree, reason: "detached, already in \(baseRef)", log: log)
            }
        }
    }
}
