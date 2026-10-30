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

    @Test func reportsFreeSpace() throws {
        let free = try #require(DiskUsage.freeSpace(at: FileManager.default.temporaryDirectory))
        #expect(free > 0)
    }
}
