import Foundation
import Testing
@testable import RepoSweepCore

struct DiskUsageTests {
    @Test func countsNestedAndHiddenFilesButNotSymlinkTargets() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-sweep-disk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let nested = dir.appendingPathComponent("a/.hidden")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let empty = try #require(DiskUsage.allocatedSize(of: dir))
        try Data(repeating: 1, count: 100_000).write(to: nested.appendingPathComponent("blob"))
        let withFile = try #require(DiskUsage.allocatedSize(of: dir))
        #expect(withFile - empty >= 100_000)

        // A link to a big file elsewhere adds nothing.
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-sweep-disk-target-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 2, count: 1_000_000).write(to: outside)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"), withDestinationURL: outside)
        #expect(try #require(DiskUsage.allocatedSize(of: dir)) < withFile + 100_000)
    }

    @Test func splitsTheTotalByNearestSubdirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-sweep-disk-split-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("group/b")
        let empty = dir.appendingPathComponent("empty")
        for sub in [a.appendingPathComponent("deep/er"), b, empty] {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 200_000).write(to: a.appendingPathComponent("deep/er/blob"))
        try Data(repeating: 2, count: 100_000).write(to: b.appendingPathComponent("blob"))
        try Data(repeating: 3, count: 50_000).write(to: dir.appendingPathComponent("loose"))

        let sizes = try #require(DiskUsage.allocatedSizes(of: dir, splitBy: [a, b, empty]))
        let sizeA = try #require(sizes.subdirs[a]), sizeB = try #require(sizes.subdirs[b])
        #expect(sizeA >= 200_000 && sizeA < 300_000)
        #expect(sizeB >= 100_000 && sizeB < 200_000)
        #expect(sizes.subdirs[empty] == 0)
        #expect(sizes.total >= sizeA + sizeB + 50_000)
        #expect(sizes.total == DiskUsage.allocatedSize(of: dir))
    }

    @Test func reportsFreeSpace() throws {
        let free = try #require(DiskUsage.freeSpace(at: FileManager.default.temporaryDirectory))
        #expect(free > 0)
    }
}
