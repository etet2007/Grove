import XCTest
@testable import MyGit

final class BranchSwitchTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MyGitBranchTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        try "initial\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: root.path)
        _ = try GitClient.text(["branch", "feature/test"], in: root.path)
        return root
    }

    func testLocalBranchesAndSwitchPreserveCompatibleStagedAndUntrackedChanges() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["update-ref", "refs/remotes/origin/remote-only", "HEAD"], in: root.path)
        XCTAssertEqual(try GitClient.localBranches(in: root.path).map(\.name), ["feature/test", "main"])
        try "staged\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "tracked.txt"], in: root.path)
        try "unstaged\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let status = try GitClient.text(["status", "--porcelain"], in: root.path)
        let index = try GitClient.text(["show", ":tracked.txt"], in: root.path)
        try GitClient.switchBranch("feature/test", in: root.path)
        XCTAssertEqual(try GitClient.text(["branch", "--show-current"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines), "feature/test")
        XCTAssertEqual(try GitClient.text(["status", "--porcelain"], in: root.path), status)
        XCTAssertEqual(try GitClient.text(["show", ":tracked.txt"], in: root.path), index)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("tracked.txt")), "unstaged\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("new.txt")), "untracked\n")
        XCTAssertThrowsError(try GitClient.switchBranch("remote-only", in: root.path))
    }

    func testConflictingChangesAndOccupiedBranchAreNeverForced() throws {
        let root = try fixture()
        let other = root.deletingLastPathComponent().appendingPathComponent("MyGitOther-\(UUID())")
        defer {
            try? FileManager.default.removeItem(at: other)
            try? FileManager.default.removeItem(at: root)
        }
        try GitClient.switchBranch("feature/test", in: root.path)
        try "feature\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "feature"], in: root.path)
        try GitClient.switchBranch("main", in: root.path)
        try "my edits\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        let head = try GitClient.text(["rev-parse", "HEAD"], in: root.path)
        XCTAssertThrowsError(try GitClient.switchBranch("feature/test", in: root.path))
        XCTAssertEqual(try GitClient.text(["rev-parse", "HEAD"], in: root.path), head)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("tracked.txt")), "my edits\n")
        _ = try GitClient.text(["worktree", "add", other.path, "feature/test"], in: root.path)
        let occupied = try XCTUnwrap(GitClient.localBranches(in: root.path).first { $0.name == "feature/test" })
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(occupied.checkoutPath)).resolvingSymlinksInPath().path,
                       other.resolvingSymlinksInPath().path)
        XCTAssertThrowsError(try GitClient.switchBranch("feature/test", in: root.path))
        XCTAssertEqual(try GitClient.text(["rev-parse", "HEAD"], in: root.path), head)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("tracked.txt")), "my edits\n")
    }

    @MainActor
    func testSwitchKeepsSelectedCheckoutAndPersistsGroupOverride() async throws {
        let root = try fixture()
        let checkout = root.deletingLastPathComponent().appendingPathComponent("MyGitCheckout-\(UUID())")
        defer {
            try? FileManager.default.removeItem(at: checkout)
            try? FileManager.default.removeItem(at: root)
        }
        _ = try GitClient.text(["worktree", "add", checkout.path, "feature/test"], in: root.path)
        _ = try GitClient.text(["branch", "other"], in: root.path)
        let group = WorktreeGroup(name: "feature/test", branch: "feature/test")
        let repository = Repository(name: "Test", path: root.path, groupID: UUID())
        let project = Project(name: "Test", repositories: [repository], worktreeGroups: [group])
        let configURL = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                               selectedWorktreeGroupID: group.id)).write(to: configURL)
        let model = AppModel(configURL: configURL)
        model.automaticRefreshEnabled = false
        try await waitForRefresh(model)
        let selectedPath = try XCTUnwrap(model.snapshots.first?.selected?.path)
        XCTAssertEqual(URL(fileURLWithPath: selectedPath).resolvingSymlinksInPath().path,
                       checkout.resolvingSymlinksInPath().path)
        await model.switchBranch("other", for: repository.id, checkoutPath: selectedPath)
        try await waitForRefresh(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
        XCTAssertEqual(model.snapshots.first?.selected?.path, selectedPath)
        XCTAssertEqual(model.snapshots.first?.selected?.branch, "other")
        let saved = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(saved.projects.first?.worktreeGroups.first { $0.id == group.id }?.selections[repository.id], selectedPath)
        await model.switchBranch("main", for: repository.id, checkoutPath: selectedPath)
        try await waitForRefresh(model)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.snapshots.first?.selected?.branch, "other")
    }

    @MainActor
    private func waitForRefresh(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
    }
}
