import XCTest
@testable import Grove

final class CommitGraphTests: XCTestCase {
    private let repositoryID = UUID()

    private func commit(_ hash: String, _ parents: [String] = []) -> Commit {
        Commit(repositoryID: repositoryID, hash: hash, committer: "Test", date: Date(),
               subject: hash, parents: parents)
    }

    func testMergeSplitsAndRejoinsAtSharedAncestor() {
        let graph = CommitGraph(commits: [commit("merge", ["main", "feature"]),
                                          commit("main", ["base"]),
                                          commit("feature", ["base"]), commit("base")])
        XCTAssertEqual(graph.laneCount, 2)
        XCTAssertEqual(graph.rows.map(\.lane), [0, 0, 1, 0])
        XCTAssertTrue(graph.rows[0].incoming.isEmpty)
        XCTAssertEqual(graph.rows[0].outgoing.map(\.to), [0, 1])
        XCTAssertTrue(graph.rows[1].outgoing.contains { $0.from == 1 && $0.to == 1 },
                      "The feature line must pass uninterrupted through the main commit")
        XCTAssertTrue(graph.rows[2].outgoing.contains { $0.from == 1 && $0.to == 0 },
                      "Feature must reconnect to the shared ancestor")
        XCTAssertTrue(graph.rows[3].outgoing.isEmpty)
    }

    func testParentOutsideLoadedPageContinuesAndLayoutSurvivesPagination() {
        let commits = [commit("merge", ["main", "feature"]), commit("main", ["base"]),
                       commit("feature", ["base"]), commit("base", ["older"])]
        let page = CommitGraph(commits: Array(commits.prefix(2)))
        let expanded = CommitGraph(commits: commits)
        XCTAssertEqual(page.rows.map(\.lane), Array(expanded.rows.prefix(2)).map(\.lane))
        XCTAssertEqual(page.rows.map(\.outgoing), Array(expanded.rows.prefix(2)).map(\.outgoing))
        XCTAssertEqual(expanded.rows.last?.outgoing.count, 1)
        let firstRowOnly = CommitGraph(commits: Array(commits.prefix(1)))
        XCTAssertEqual(firstRowOnly.tracks.count, 2, "Track names include a lane whose first node is outside the page")
    }

    func testOctopusMergeUsesSeparateLanesAndRootsEnd() {
        let graph = CommitGraph(commits: [commit("merge", ["a", "b", "c"]),
                                          commit("a"), commit("b"), commit("c")])
        XCTAssertEqual(graph.laneCount, 3)
        XCTAssertEqual(graph.rows[0].outgoing.map(\.to), [0, 1, 2])
        XCTAssertTrue(graph.rows.last!.outgoing.isEmpty)
    }

    func testTracksUseActualBranchTipsAndKeepUnnamedTracks() {
        var tip = commit("merge", ["main", "feature"])
        tip.branchNames = ["main", "release"]
        var feature = commit("feature", ["base"])
        feature.branchNames = ["feature/search"]
        let graph = CommitGraph(commits: [tip, commit("main", ["base"]), feature, commit("base")])
        XCTAssertEqual(graph.tracks.map(\.branches), [["main", "release"], ["feature/search"]])
        let unnamed = CommitGraph(commits: [tip, commit("main", ["base"]),
                                           commit("feature", ["base"]), commit("base")])
        XCTAssertEqual(unnamed.tracks[1].branches, [])
    }

    func testHoverTargetsOnlyTheNearestLineIncludingDiagonalAndScaledNodes() {
        let graph = CommitGraph(commits: [commit("merge", ["main", "feature"]),
                                          commit("main", ["base"]), commit("feature", ["base"])])
        let merge = CommitGraphHitMap(row: graph.rows[0], height: 30, scale: 1)
        XCTAssertEqual(merge.color(at: CGPoint(x: 7, y: 25)), 0)
        XCTAssertEqual(merge.color(at: CGPoint(x: 15, y: 25)), 1)
        XCTAssertNil(merge.color(at: CGPoint(x: 19, y: 2)))
        let parallel = CommitGraphHitMap(row: graph.rows[1], height: 30, scale: 1)
        XCTAssertEqual(parallel.color(at: CGPoint(x: 7, y: 4)), 0)
        XCTAssertEqual(parallel.color(at: CGPoint(x: 19, y: 4)), 1)
        XCTAssertNil(parallel.color(at: CGPoint(x: 13, y: 4)))
        let scaled = CommitGraphHitMap(row: graph.rows[0], height: 45, scale: 1.5)
        XCTAssertEqual(scaled.color(at: CGPoint(x: 10.5, y: 22.5)), 0)
        XCTAssertEqual(scaled.color(at: CGPoint(x: 22.5, y: 37.5)), 1)
    }

    func testBranchDecorationsUpdateWithoutReloadingHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveGraphRefs-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String { try GitClient.text(args, in: root.path) }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Test"])
        _ = try git(["config", "user.email", "test@example.invalid"])
        _ = try git(["-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "base"])
        _ = try git(["branch", "feature/search"])
        let history = try GitClient.commits(in: root.path, repositoryID: repositoryID, limit: 20)
        let decorated = try GitClient.decoratingBranches(history, in: root.path)
        XCTAssertEqual(decorated.first?.branchNames, ["feature/search", "main"])
        _ = try git(["branch", "-m", "feature/search", "feature/renamed"])
        XCTAssertEqual(try GitClient.decoratingBranches(decorated, in: root.path).first?.branchNames,
                       ["feature/renamed", "main"])
        _ = try git(["branch", "-D", "feature/renamed"])
        XCTAssertEqual(try GitClient.decoratingBranches(decorated, in: root.path).first?.branchNames, ["main"])
        XCTAssertEqual(decorated.first?.hash, history.first?.hash)
    }

    func testTopologyWinsOverClockSkewWithoutLosingIndependentOrdering() {
        let ordered = CommitGraph.topologicalOrder([
            commit("base"), commit("feature", ["base"]),
            commit("merge", ["main", "feature"]), commit("main", ["base"])
        ])
        XCTAssertEqual(ordered.map(\.hash), ["merge", "feature", "main", "base"])
    }
}
