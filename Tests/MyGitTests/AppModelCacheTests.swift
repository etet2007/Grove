import XCTest
@testable import MyGit

final class AppModelCacheTests: XCTestCase {
    @MainActor
    func testReturningToGroupImmediatelyRestoresFilesAndCommitsThenRefreshes() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MyGitCacheTests-\(UUID())")
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

        model.selectWorktreeGroup(secondary.id)
        try await waitForRefresh(model)
        XCTAssertEqual(model.snapshots.first?.selected?.path, featurePath)
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
    private func waitForRefresh(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRefreshing, "Refresh timed out")
    }
}
