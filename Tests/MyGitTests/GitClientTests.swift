import XCTest
@testable import MyGit

final class GitClientTests: XCTestCase {
    func testWorktreeDiscoveryStatusAndDiff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitTests-\(UUID().uuidString)")
        let main = root.appendingPathComponent("main")
        let feature = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func git(_ arguments: [String], at path: URL = main) throws -> String {
            try GitClient.text(arguments, in: path.path)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "MyGit Test"])
        _ = try git(["config", "user.email", "mygit@example.invalid"])
        try "first\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "initial"])
        _ = try git(["worktree", "add", "-b", "feature/test", feature.path])

        let trees = try GitClient.worktrees(in: main.path)
        XCTAssertEqual(trees.count, 2)
        XCTAssertTrue(trees.contains(where: { $0.isPrimary && $0.branch == "main" }))
        XCTAssertTrue(trees.contains(where: { !$0.isPrimary && $0.branch == "feature/test" }))

        let tracked = feature.appendingPathComponent("tracked.txt")
        try "first\nsecond\n".write(to: tracked, atomically: true, encoding: .utf8)
        _ = try git(["add", "tracked.txt"], at: feature)
        try "first\nsecond\nthird\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "new\n".write(to: feature.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let files = try GitClient.changedFiles(in: feature.path, repositoryID: UUID())
        let changed = try XCTUnwrap(files.first(where: { $0.path == "tracked.txt" }))
        XCTAssertTrue(changed.hasStaged)
        XCTAssertTrue(changed.hasUnstaged)
        XCTAssertTrue(files.contains(where: { $0.path == "new.txt" && $0.isUntracked }))
        XCTAssertTrue(try GitClient.diff(for: changed, in: feature.path, mode: .unstaged).contains("+third"))
        XCTAssertTrue(try GitClient.diff(for: changed, in: feature.path, mode: .staged).contains("+second"))
        XCTAssertEqual(try GitClient.commits(in: feature.path, repositoryID: UUID(), limit: 10).first?.subject, "initial")
    }

    func testGroupSelectsMatchingBranchThenPrimaryUnlessOverridden() {
        let repositoryID = UUID()
        let primary = Worktree(path: "/main", branch: "main", head: "a", isPrimary: true, isDetached: false)
        let feature = Worktree(path: "/feature", branch: "feature", head: "b", isPrimary: false, isDetached: false)
        let other = Worktree(path: "/other", branch: "other", head: "c", isPrimary: false, isDetached: false)
        var group = WorktreeGroup(name: "feature", branch: "feature")
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, feature, other]), feature)
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, other]), primary)
        group.selections[repositoryID] = other.path
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, feature, other]), other)
    }

    func testManualWorktreeChoiceSurvivesConfigurationRoundTrip() throws {
        let repositoryID = UUID()
        var group = WorktreeGroup(name: "feature", branch: "feature")
        group.selections[repositoryID] = "/worktrees/feature"
        var project = Project(name: "Android")
        project.worktreeGroups = [group]
        let original = Configuration(projects: [project], selectedProjectID: project.id,
                                     selectedWorktreeGroupID: group.id)
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.projects[0].worktreeGroups[0].selections[repositoryID], "/worktrees/feature")
        XCTAssertEqual(restored.selectedWorktreeGroupID, group.id)
    }
}
