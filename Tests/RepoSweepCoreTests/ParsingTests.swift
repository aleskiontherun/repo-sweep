import Foundation
import Testing
@testable import RepoSweepCore

@Suite struct GitHubRepoParsing {
    @Test(arguments: [
        "git@github.com:octo/hello.git",
        "git@github.com:octo/hello",
        "ssh://git@github.com/octo/hello.git",
        "ssh://git@github.com:22/octo/hello.git",
        "https://github.com/octo/hello.git",
        "https://github.com/octo/hello/",
        "https://user@github.com/octo/hello",
        "github-work:octo/hello.git",
    ])
    func parses(_ remote: String) {
        #expect(GitHubRepo(remoteURL: remote) == GitHubRepo(owner: "octo", name: "hello"))
    }

    @Test(arguments: [
        "git@gitlab.com:octo/hello.git",
        "/srv/git/hello.git",
        "https://github.com/octo",
    ])
    func rejects(_ remote: String) {
        #expect(GitHubRepo(remoteURL: remote) == nil)
    }
}

@Suite struct PullRequestDecoding {
    func pr(rollup: String, extra: String = "") throws -> PullRequest {
        let json = """
        [{"number": 7, "title": "Add thing", "url": "https://github.com/octo/hello/pull/7",
          "isDraft": false, "author": {"login": "octo"}, "headRefName": "feature/thing",
          "reviewDecision": "APPROVED", "mergeable": "CONFLICTING",
          "updatedAt": "2026-10-29T12:00:00Z", "statusCheckRollup": \(rollup) \(extra)}]
        """
        return try #require(PullRequests.decode(json).first)
    }

    @Test func fields() throws {
        let pr = try pr(rollup: "[]")
        #expect(pr.number == 7)
        #expect(pr.author?.login == "octo")
        #expect(pr.review == .approved)
        #expect(pr.hasConflicts)
        #expect(pr.checks == .none)
    }

    @Test func passing() throws {
        let pr = try pr(rollup: """
        [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"},
         {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SKIPPED"},
         {"__typename": "StatusContext", "state": "SUCCESS"}]
        """)
        #expect(pr.checks == .passing)
    }

    @Test func pending() throws {
        let pr = try pr(rollup: """
        [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"},
         {"__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": ""}]
        """)
        #expect(pr.checks == .pending)
    }

    @Test func failingWinsOverPending() throws {
        let pr = try pr(rollup: """
        [{"__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": ""},
         {"__typename": "StatusContext", "state": "FAILURE"}]
        """)
        #expect(pr.checks == .failing)
    }
}
