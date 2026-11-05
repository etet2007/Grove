import XCTest
@testable import Grove

final class AppModelCacheTests: XCTestCase {
    @MainActor
    func testReturningToGroupImmediatelyRestoresFilesAndCommitsThenRefreshes() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GroveCacheTests-\(UUID())")
        let main = root.appendingPathComponent("main")
        let feature = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: main.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: main.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: main.path)
        try "initial\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: main.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: main.path)
        _ = try GitClient.text(["worktree", "add", "-b", "feature", feature.path], in: main.path)
        let trees = try GitClient.worktrees(in: main.path)
        let mainPath = try XCTUnwrap(trees.first(where: \.isPrimary)?.path)
        let featurePath = try XCTUnwrap(trees.first(where: { !$0.isPrimary })?.path)
        try "modified\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        let primary = WorktreeGroup(name: "主目录", isPrimary: true)
        let secondary = WorktreeGroup(name: "feature", branch: "feature")
        var project = Project(name: "Test")
        project.worktreeGroups = [primary, secondary]
        project.repositories = [Repository(name: "main", path: main.path, groupID: UUID())]
        let configURL = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                               selectedWorktreeGroupID: primary.id)).write(to: configURL)
        let model = AppModel(configURL: configURL)
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.files.count, 1)
        XCTAssertEqual(model.commits.first?.subject, "initial")

        let forcedCounts = model.lastRefreshCommandCounts
        XCTAssertEqual(forcedCounts["log"], 1)
        model.refresh(useCachedHistory: true)
        try await waitForRefresh(model)
        XCTAssertNil(model.lastRefreshCommandCounts["log"])
        XCTAssertNil(model.lastRefreshCommandCounts["remote"])
        XCTAssertNil(model.lastRefreshCommandCounts["config"])
        print("PERF cached refresh: \(forcedCounts.values.reduce(0, +)) → \(model.lastRefreshCommandCounts.values.reduce(0, +)) Git commands")
        model.refresh()
        try await waitForRefresh(model)
        XCTAssertEqual(model.lastRefreshCommandCounts["log"], 1)

        let file = try XCTUnwrap(model.snapshots.first?.files.first)
        let commit = try XCTUnwrap(model.commits.first)
        model.selectFile(file)
        model.diffMode = .all
        model.loadDetail()
        try await waitForDetail(model.detailStates[0])
        let fileDiff = model.detail
        model.activeTab = 1
        XCTAssertNil(model.selectedFile)
        XCTAssertTrue(model.detail.isEmpty)
        model.selectCommit(commit)
        try await waitForDetail(model.detailStates[1])
        let commitDiff = model.detail
        XCTAssertNotNil(model.detailStates[1].commitPatch)
        model.activeTab = 0
        XCTAssertEqual(model.selectedFile, file)
        XCTAssertNil(model.selectedCommit)
        XCTAssertEqual(model.diffMode, .all)
        XCTAssertEqual(model.detail, fileDiff)
        model.activeTab = 1
        XCTAssertEqual(model.selectedCommit, commit)
        XCTAssertNil(model.selectedFile)
        XCTAssertEqual(model.detail, commitDiff)
        model.refresh()
        try await waitForRefresh(model)
        XCTAssertEqual(model.detail, commitDiff, "Refreshing changes must not replace the commit diff")

        model.selectWorktreeGroup(secondary.id)
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.selected?.path, featurePath)
        XCTAssertTrue(model.detailStates.allSatisfy { $0.selectedFile == nil && $0.selectedCommit == nil })
        XCTAssertEqual(model.snapshots.first?.files.count, 0)
        try "new\n".write(to: main.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        model.selectWorktreeGroup(primary.id)
        // No await: cached content must be available in the same UI turn.
        XCTAssertEqual(model.snapshots.first?.selected?.path, mainPath)
        XCTAssertEqual(model.snapshots.first?.files.count, 1)
        XCTAssertEqual(model.commits.first?.subject, "initial")
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.files.count, 2)

        model.selectWorktree(featurePath, for: project.repositories[0].id)
        XCTAssertFalse(model.snapshots.contains(where: { $0.selected?.path == mainPath }))
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.selected?.path, featurePath)
        model.selectWorktree(nil, for: project.repositories[0].id)
        XCTAssertEqual(model.snapshots.first?.selected?.path, mainPath)
        try await waitForRefresh(model)

        // A new HEAD must invalidate the history reused during a switch.
        try "feature change\n".write(to: feature.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: feature.path)
        _ = try GitClient.text(["commit", "-m", "feature update"], in: feature.path)
        model.selectWorktreeGroup(secondary.id)
        XCTAssertEqual(model.commits.first?.subject, "initial")
        try await waitForRefresh(model)
        XCTAssertEqual(model.commits.first?.subject, "feature update")

        model.selectWorktreeGroup(primary.id)
        model.selectWorktreeGroup(secondary.id)
        model.selectWorktreeGroup(primary.id)
        XCTAssertEqual(model.snapshots.first?.selected?.path, mainPath)
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.selected?.path, mainPath)
        XCTAssertEqual(model.commits.first?.subject, "initial")
    }

    @MainActor
    private func waitForDetail(_ state: DetailState) async throws {
        let deadline = Date().addingTimeInterval(10)
        while (state.detail.isEmpty || state.detail == "正在读取…") && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(state.detail.isEmpty)
        XCTAssertNotEqual(state.detail, "正在读取…")
    }

    @MainActor
    private func waitForRefresh(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRefreshing, "Refresh timed out")
    }
}
