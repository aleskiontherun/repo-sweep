import Foundation

public enum DiskUsage {
    /// The space everything under `dir` takes up on disk, as Finder's Get
    /// Info counts it: each file's allocated size, hidden files and package
    /// contents included, symbolic links not followed. Unreadable entries
    /// are skipped rather than failing the whole count. Returns nil when the
    /// calling task is cancelled part way.
    public static func allocatedSize(of dir: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let entries = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in true }
        ) else { return nil }

        var total: Int64 = 0
        var count = 0
        for case let url as URL in entries {
            count += 1
            if count % 1000 == 0, Task.isCancelled { return nil }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return Task.isCancelled ? nil : total
    }

    /// The space free on the volume holding `url`, counting purgeable space
    /// macOS would reclaim on demand, as Finder reports it.
    public static func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                       .volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
    }
}
