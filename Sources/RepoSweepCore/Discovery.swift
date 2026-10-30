import Foundation

public enum Discovery {
    /// Directories never worth descending into, whatever the root's
    /// `.gitignore` says.
    static let skippedNames: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".Trash"]
    static let maxDepth = 6

    /// Every checkout under `root`: the root itself if it is one, plus each
    /// directory holding a `.git` below it.
    ///
    /// A checkout is a boundary the walk doesn't descend into, so a repo's
    /// submodules and vendored checkouts stay out. When the root is itself a
    /// repository, anything it ignores is skipped -- an umbrella checkout
    /// ignores its scratch areas and agent worktrees but deliberately not the
    /// sibling repos inside it. Linked worktrees found anyway are dropped:
    /// they belong to their main checkout, and its cleanup handles them.
    public static func repositories(under root: URL) async -> [URL] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootRepo = isRepo(root) ? GitRepo(path: root) : nil

        var found: [URL] = rootRepo == nil ? [] : [root]
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            var children = subdirectories(of: dir)
            if let rootRepo {
                let ignored = await ignoredPaths(children, in: rootRepo)
                children.removeAll { ignored.contains($0.path) }
            }
            for child in children {
                if isRepo(child) {
                    found.append(child)
                } else {
                    queue.append((child, depth + 1))
                }
            }
        }

        // By path: the root sorts first, and a group's repos sit together.
        found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var result: [URL] = []
        for repo in found {
            let linked = await isLinkedWorktree(repo)
            if repo == root || !linked {
                result.append(repo)
            }
        }
        return result
    }

    public static func isRepo(_ url: URL) -> Bool {
        // A worktree's `.git` is a file rather than a directory.
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    static func subdirectories(of dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys
        ) else { return [] }
        return entries
            .filter { url in
                guard !skippedNames.contains(url.lastPathComponent),
                      let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
                return values.isDirectory == true && values.isSymbolicLink != true
            }
            .map(\.standardizedFileURL)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func ignoredPaths(_ paths: [URL], in repo: GitRepo) async -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let root = repo.path.path + "/"
        let relative = paths.map { String($0.path.dropFirst(root.count)) }
        let result = await repo.git(["check-ignore", "--stdin"], stdin: relative.joined(separator: "\n") + "\n")
        // 0 = some path matched, 1 = none did, anything else is an error.
        guard result.status <= 1 else { return [] }
        return Set(result.stdout.split(separator: "\n").map { root + $0 })
    }

    static func isLinkedWorktree(_ url: URL) async -> Bool {
        let result = await GitRepo(path: url).git("rev-parse", "--path-format=absolute", "--git-common-dir")
        guard result.ok else { return false }
        let common = URL(fileURLWithPath: result.out).resolvingSymlinksInPath().path
        let own = url.appendingPathComponent(".git").resolvingSymlinksInPath().path
        return common != own
    }
}
