import XCTest
@testable import MyGit

final class ProjectManagementTests: XCTestCase {
    @MainActor
    func testWorktreeGroupOrderPersistsAcrossRefreshIncludingDetachedWorktree() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitGroupOrder-\(UUID())")
        let repo = root.appendingPathComponent("repo")
        let detached = root.appendingPathComponent("detached")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: repo.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: repo.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: repo.path)
        _ = try GitClient.text(["commit", "--allow-empty", "-m", "initial"], in: repo.path)
        _ = try GitClient.text(["worktree", "add", "--detach", detached.path], in: repo.path)
        let primary = WorktreeGroup(name: "主目录", isPrimary: true)
        let manual = WorktreeGroup(name: "Manual")
        let project = Project(name: "Test", repositories: [Repository(name: "repo", path: repo.path, groupID: UUID())],
                              worktreeGroups: [primary, manual])
        let config = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                               selectedWorktreeGroupID: manual.id)).write(to: config)
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        for _ in 0..<300 where model.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
        let detachedGroup = try XCTUnwrap(model.selectedProject?.worktreeGroups.first(where: \.isTransient))
        model.moveWorktreeGroups(from: IndexSet(integer: 2), to: 0)
        model.moveWorktreeGroups(from: IndexSet(integer: 99), to: 0)
        let expected = [detachedGroup.id, primary.id, manual.id]
        XCTAssertEqual(model.selectedProject?.worktreeGroups.map(\.id), expected)
        model.refresh()
        for _ in 0..<300 where model.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.selectedProject?.worktreeGroups.map(\.id), expected)
        let saved = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: config))
        XCTAssertEqual(saved.projects.first?.worktreeGroups.map(\.id), expected)
        XCTAssertEqual(saved.selectedWorktreeGroupID, manual.id)
    }

    @MainActor
    func testRenamingAndReorderingPersistWithoutChangingSelectionOrContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitProjects-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("config.json")
        var projects = [Project(name: "fly"), Project(name: "CI"), Project(name: "MyGit")]
        let group = WorktreeGroup(name: "主目录", isPrimary: true)
        projects[1].worktreeGroups = [group]
        projects[1].groups = [RepositoryGroup(name: "App")]
        projects[1].hiddenBranches = ["hidden"]
        try JSONEncoder().encode(Configuration(projects: projects, selectedProjectID: projects[1].id,
                                               selectedWorktreeGroupID: group.id)).write(to: configURL)
        let model = AppModel(configURL: configURL)
        model.automaticRefreshEnabled = false
        for _ in 0..<200 where model.isRefreshing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRefreshing)
        let original = model.projects[1]

        model.renameProject(original.id, name: "  CI 工程 \n")
        model.renameProject(original.id, name: " \n ")
        model.renameProject(UUID(), name: "missing")
        model.moveProjects(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(model.projects.map(\.name), ["CI 工程", "fly", "MyGit"])
        model.moveProjects(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(model.projects.map(\.name), ["fly", "MyGit", "CI 工程"])
        model.moveProjects(from: IndexSet(integer: 8), to: 0)
        model.moveProjects(from: IndexSet(integer: 0), to: -1)
        model.moveProjects(from: IndexSet(integer: 0), to: 4)

        let restored = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        XCTAssertEqual(restored.projects, model.projects)
        XCTAssertEqual(restored.selectedProjectID, original.id)
        XCTAssertEqual(restored.selectedWorktreeGroupID, group.id)
        XCTAssertEqual(model.selectedProjectID, original.id)
        XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
        var renamed = original
        renamed.name = "CI 工程"
        XCTAssertEqual(restored.projects.last, renamed)
    }
}
