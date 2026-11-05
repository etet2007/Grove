import XCTest
@testable import Grove

final class CommitBrowserTests: XCTestCase {
    @MainActor
    func testRepositoryBrowsingKeepsSeparateSelectionsAndPaginatesOnlyCurrentHistory() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("GroveCommitBrowser-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = Project(name: "Test")
        let group = WorktreeGroup(name: "主目录", isPrimary: true)
        project.worktreeGroups = [group]
        for name in ["App", "Library"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try GitClient.text(["init", "-b", "main"], in: directory.path)
            _ = try GitClient.text(["config", "user.name", "Test"], in: directory.path)
            _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: directory.path)
            try "initial\n".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            _ = try GitClient.text(["add", "."], in: directory.path)
            _ = try GitClient.text(["commit", "-m", "\(name) initial"], in: directory.path)
            for index in 1...31 {
                _ = try GitClient.text(["commit", "--allow-empty", "-m", "\(name) \(index)"], in: directory.path)
            }
            try "modified\n".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            project.repositories.append(Repository(name: name, path: directory.path, groupID: UUID()))
        }
        let config = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                               selectedWorktreeGroupID: group.id)).write(to: config)
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        try await waitForRefresh(model)
        let app = project.repositories[0].id
        let library = project.repositories[1].id
        XCTAssertEqual(model.commitRepositoryID, app)
        XCTAssertNil(model.focusedRepositoryID)
        XCTAssertEqual(model.visibleCommits.count, 30)
        XCTAssertEqual(model.lastRefreshCommandCounts["log"], 1, "Initially load only the default repository")
        XCTAssertTrue(model.commits.allSatisfy { $0.repositoryID == app })
        XCTAssertTrue(model.visibleCommits.allSatisfy { $0.repositoryID == app })

        let file = try XCTUnwrap(model.snapshots.first?.files.first)
        model.selectFile(file)
        model.activeTab = 1
        let appCommit = try XCTUnwrap(model.visibleCommits.first)
        model.selectCommit(appCommit)
        let appState = model.detailStates[1]
        model.selectBrowsingRepository(library)
        try await waitForRefresh(model)
        XCTAssertNil(model.selectedCommit)
        let libraryCommit = try XCTUnwrap(model.visibleCommits.first)
        model.selectCommit(libraryCommit)
        model.selectBrowsingRepository(app)
        XCTAssertEqual(model.selectedCommit, appCommit)
        XCTAssertTrue(model.detailStates[1] === appState)
        model.activeTab = 0
        XCTAssertNil(model.browsingRepositoryID)
        XCTAssertEqual(model.selectedFile, file)
        model.selectBrowsingRepository(library)
        XCTAssertNil(model.selectedFile, "Filtering changes must clear details from another repository")
        model.activeTab = 1
        XCTAssertEqual(model.browsingRepositoryID, library)
        XCTAssertEqual(model.selectedCommit, libraryCommit)
        model.selectCommitRepository(app)
        model.loadMoreCommits()
        try await waitForRefresh(model)
        XCTAssertEqual(model.visibleCommits.count, 32)
        XCTAssertEqual(model.commits.filter { $0.repositoryID == library }.count, 30)
        XCTAssertEqual(model.lastRefreshCommandCounts["log"], 1, "Other repositories reuse their cached histories")
        model.selectCommitRepository(nil)
        XCTAssertEqual(model.visibleCommits.count, 62)
        XCTAssertNil(model.selectedCommit)
        model.selectCommitRepository(library)
        XCTAssertEqual(model.selectedCommit, libraryCommit)
        // File selection wins over an earlier module interaction without filtering Changes.
        model.activeTab = 0
        model.selectBrowsingRepository(nil)
        model.rememberChangesRepository(app)
        let libraryFile = try XCTUnwrap(model.snapshots.first { $0.repository.id == library }?.files.first)
        model.selectFile(libraryFile)
        XCTAssertNil(model.focusedRepositoryID)
        model.activeTab = 1
        XCTAssertEqual(model.commitRepositoryID, library)
        XCTAssertEqual(model.selectedCommit, libraryCommit)

        // Manual History navigation survives a tab round trip with no new Changes selection.
        model.selectCommitRepository(app)
        model.activeTab = 0
        model.activeTab = 1
        XCTAssertEqual(model.commitRepositoryID, app)
        XCTAssertEqual(model.selectedCommit, appCommit)

        // A module title can override the previously selected file, including a collapsed module.
        model.activeTab = 0
        model.rememberChangesRepository(app)
        model.activeTab = 1
        XCTAssertEqual(model.commitRepositoryID, app)
        model.activeTab = 0
        model.selectBrowsingRepository(nil)
        model.activeTab = 1
        XCTAssertNil(model.commitRepositoryID)

        // Checkout changes discard a pending target along with the old details.
        model.selectCommitRepository(library)
        model.activeTab = 0
        model.rememberChangesRepository(app)
        model.selectWorktreeGroup(group.id)
        try await waitForRefresh(model)
        model.activeTab = 1
        XCTAssertEqual(model.commitRepositoryID, library)
        XCTAssertNil(model.selectedCommit, "Checkout selection resets all commit details")
        model.removeRepository(library)
        try await waitForRefresh(model)
        XCTAssertEqual(model.commitRepositoryID, app)
        XCTAssertTrue(model.visibleCommits.allSatisfy { $0.repositoryID == app })
    }

    @MainActor private func waitForRefresh(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(15)
        while model.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
    }
}
