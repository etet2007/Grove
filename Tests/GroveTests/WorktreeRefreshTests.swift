import XCTest
@testable import Grove

final class WorktreeRefreshTests: XCTestCase {
    @MainActor
    func testExternalBranchChangesKeepTheSelectedCheckout() async throws {
        for scenario in ["branch-switch", "detached-reattach", "failed-scan-then-detach"] {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("GroveBranchRefresh-\(UUID())")
            let repo = root.appendingPathComponent("repo")
            let checkout = root.appendingPathComponent("checkout")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try GitClient.text(["init", "-b", "main"], in: repo.path)
            _ = try GitClient.text(["config", "user.name", "Test"], in: repo.path)
            _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: repo.path)
            _ = try GitClient.text(["commit", "--allow-empty", "-m", "initial"], in: repo.path)
            _ = try GitClient.text(scenario == "detached-reattach"
                ? ["worktree", "add", "--detach", checkout.path]
                : ["worktree", "add", "-b", "feature", checkout.path], in: repo.path)
            let repository = Repository(name: "repo", path: repo.path, groupID: UUID())
            let primary = WorktreeGroup(name: "主目录", isPrimary: true)
            let project = Project(name: "Test", repositories: [repository], worktreeGroups: [primary])
            let config = root.appendingPathComponent("config.json")
            try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                                   selectedWorktreeGroupID: primary.id)).write(to: config)
            let model = AppModel(configURL: config)
            model.automaticRefreshEnabled = false
            try await waitForRefresh(model)
            let group = try XCTUnwrap(model.selectedProject?.worktreeGroups.first(where: { !$0.isPrimary }))
            model.selectWorktreeGroup(group.id)
            try await waitForRefresh(model)

            if scenario == "failed-scan-then-detach" {
                let metadata = repo.appendingPathComponent(".git")
                let hidden = root.appendingPathComponent("saved-git")
                try FileManager.default.moveItem(at: metadata, to: hidden)
                model.refresh()
                try await waitForRefresh(model)
                try FileManager.default.moveItem(at: hidden, to: metadata)
            }
            _ = try GitClient.text(scenario == "failed-scan-then-detach"
                ? ["switch", "--detach"] : ["switch", "-c", "other"], in: checkout.path)
            model.refresh()
            try await waitForRefresh(model)
            XCTAssertEqual(model.selectedWorktreeGroupID, group.id, scenario)
            XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path), scenario)
            XCTAssertNil(model.notice, scenario)
            let reopened = AppModel(configURL: config)
            reopened.automaticRefreshEnabled = false
            try await waitForRefresh(reopened)
            XCTAssertEqual(reopened.selectedWorktreeGroupID, group.id, scenario)
            XCTAssertEqual(reopened.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path), scenario)
        }
    }

    @MainActor
    func testFailedScanPreservesGroupAndSelectionUntilSuccessfulScan() async throws {
        for (detached, manual) in [(false, false), (false, true), (true, false)] {
            let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent("GroveWorktreeRefresh-\(UUID())")
            let repo = root.appendingPathComponent("repo")
            let checkout = root.appendingPathComponent("checkout")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try GitClient.text(["init", "-b", "main"], in: repo.path)
            _ = try GitClient.text(["config", "user.name", "Test"], in: repo.path)
            _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: repo.path)
            _ = try GitClient.text(["commit", "--allow-empty", "-m", "initial"], in: repo.path)
            _ = try GitClient.text(detached
                ? ["worktree", "add", "--detach", checkout.path]
                : ["worktree", "add", "-b", "feature", checkout.path], in: repo.path)
            let repository = Repository(name: "repo", path: repo.path, groupID: UUID())
            let primary = WorktreeGroup(name: "主目录", isPrimary: true)
            let project = Project(name: "Test", repositories: [repository], worktreeGroups: [primary])
            let config = root.appendingPathComponent("config.json")
            try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                                   selectedWorktreeGroupID: primary.id)).write(to: config)
            let model = AppModel(configURL: config)
            model.automaticRefreshEnabled = false
            try await waitForRefresh(model)
            let group = try XCTUnwrap(model.selectedProject?.worktreeGroups.first(where: { !$0.isPrimary }))
            model.selectWorktreeGroup(group.id)
            try await waitForRefresh(model)
            XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
            if manual {
                model.selectWorktree(canonicalFilesystemPath(checkout.path), for: repository.id)
                try await waitForRefresh(model)
            }
            let before = try XCTUnwrap(model.selectedProject)
            let savedBefore = try Data(contentsOf: config)

            // Fail the actual Git worktree scan without touching any user repository.
            let metadata = repo.appendingPathComponent(".git")
            let hiddenMetadata = root.appendingPathComponent("saved-git")
            try FileManager.default.moveItem(at: metadata, to: hiddenMetadata)
            model.refresh()
            try await waitForRefresh(model)
            XCTAssertEqual(model.selectedWorktreeGroupID, group.id, "A read failure must not switch to the primary group")
            XCTAssertEqual(model.selectedProject, before, "A read failure must not remove discovered groups or manual selections")
            XCTAssertEqual(try Data(contentsOf: config), savedBefore, "A failed scan must not persist missing worktrees")
            XCTAssertNotNil(model.snapshots.first?.error)
            XCTAssertNil(model.notice)

            try FileManager.default.moveItem(at: hiddenMetadata, to: metadata)
            model.refresh()
            try await waitForRefresh(model)
            XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
            XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
            XCTAssertNil(model.snapshots.first?.error)

            // Git can exit successfully while a linked checkout's HEAD is unreadable.
            let head = URL(fileURLWithPath: try GitClient.text(["rev-parse", "--absolute-git-dir"], in: checkout.path).trimmingCharacters(in: .whitespacesAndNewlines))
                .appendingPathComponent("HEAD")
            let originalHead = try Data(contentsOf: head)
            for incompleteHead: Data? in [Data(), Data("ref: refs/heads/".utf8), nil] {
                if let incompleteHead { try incompleteHead.write(to: head) }
                else { try FileManager.default.removeItem(at: head) }
                model.refresh()
                try await waitForRefresh(model)
                XCTAssertEqual(model.selectedWorktreeGroupID, group.id, "An unreadable HEAD must not switch to the primary group")
                XCTAssertEqual(model.selectedProject, before)
                XCTAssertEqual(try Data(contentsOf: config), savedBefore)
                XCTAssertNotNil(model.snapshots.first?.error)
                XCTAssertNil(model.notice)
                try originalHead.write(to: head)
                model.refresh()
                try await waitForRefresh(model)
                XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
                XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
            }

            if !detached {
                _ = try GitClient.text(["switch", "--detach"], in: checkout.path)
                model.refresh()
                try await waitForRefresh(model)
                XCTAssertEqual(model.selectedWorktreeGroupID, group.id, "A checkout entering detached HEAD must not switch the current group")
                XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
                XCTAssertTrue(model.snapshots.first?.selected?.isDetached == true)
                let reopened = AppModel(configURL: config)
                reopened.automaticRefreshEnabled = false
                try await waitForRefresh(reopened)
                XCTAssertEqual(reopened.selectedWorktreeGroupID, group.id)
                XCTAssertEqual(reopened.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
                _ = try GitClient.text(["switch", "feature"], in: checkout.path)
                model.refresh()
                try await waitForRefresh(model)
                XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
                XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(checkout.path))
            }

            // A successful scan still removes genuinely deleted worktrees.
            _ = try GitClient.text(["worktree", "remove", checkout.path], in: repo.path)
            model.refresh()
            try await waitForRefresh(model)
            if !detached {
                XCTAssertNil(model.selectedGroup?.selections[repository.id])
                model.refresh()
                try await waitForRefresh(model)
            }
            XCTAssertFalse(model.selectedProject!.worktreeGroups.contains(where: { $0.id == group.id }))
            XCTAssertEqual(model.selectedWorktreeGroupID, primary.id)
        }
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
