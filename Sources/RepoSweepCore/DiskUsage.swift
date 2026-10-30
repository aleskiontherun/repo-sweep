import Foundation

public enum DiskUsage {
    /// The space everything under `dir` takes up on disk, as Finder's Get
    /// Info counts it: each file's allocated size, hidden files and package
    /// contents included, symbolic links not followed. Unreadable entries
    /// are skipped rather than failing the whole count. Returns nil when the
    /// calling task is cancelled part way.
    public static func allocatedSize(of dir: URL) -> Int64? {
        allocatedSizes(of: dir, splitBy: [])?.total
    }

    /// `allocatedSize(of: dir)`, plus the share of it under each of
    /// `subdirs`, counted in the same walk so a big tree is read once. Each
    /// file counts towards the nearest of `subdirs` that contains it; every
    /// one of `subdirs` gets an entry, 0 when nothing under `dir` is in it.
    public static func allocatedSizes(of dir: URL, splitBy subdirs: [URL]) -> (total: Int64, subdirs: [URL: Int64])? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let entries = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in true }
        ) else { return nil }

        // The enumerator hands out real paths (/private/var/… for /var/…),
        // so each of `subdirs` is known by its real path and by its path as
        // given.
        let owners = Dictionary(subdirs.flatMap { sub in
            [(sub.standardizedFileURL.path, sub), (realPath(sub), sub)]
        }, uniquingKeysWith: { first, _ in first })
        var sizes = Dictionary(subdirs.map { ($0, Int64(0)) }, uniquingKeysWith: { first, _ in first })
        // The owner of each directory seen so far, so a file costs one lookup.
        var ownerOfDir: [String: URL?] = [:]
        func owner(ofDir path: String) -> URL? {
            if let known = ownerOfDir[path] { return known }
            let found: URL?
            if let own = owners[path] {
                found = own
            } else if path == "/" || path.isEmpty {
                found = nil
            } else {
                found = owner(ofDir: (path as NSString).deletingLastPathComponent)
            }
            ownerOfDir[path] = found
            return found
        }

        var total: Int64 = 0
        var count = 0
        for case let url as URL in entries {
            count += 1
            if count % 1000 == 0, Task.isCancelled { return nil }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            total += size
            if !owners.isEmpty, let sub = owner(ofDir: url.deletingLastPathComponent().path) {
                sizes[sub, default: 0] += size
            }
        }
        return Task.isCancelled ? nil : (total, sizes)
    }

    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The space free on the volume holding `url`, counting purgeable space
    /// macOS would reclaim on demand, as Finder reports it.
    public static func freeSpace(at url: URL) -> Int64? {
        // A URL caches the resource values it has read, so asking the same
        // one again would only repeat the first answer.
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                       .volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
    }
}
