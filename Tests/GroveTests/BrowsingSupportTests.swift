import AppKit
import XCTest
@testable import Grove

final class BrowsingSupportTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("GroveBrowsing-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func repository(_ root: URL) throws {
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Search Tester"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "search@example.invalid"], in: root.path)
    }

    func testConfigurationBackupSurvivesCorruptionAndRecoveryPreservesDamagedFile() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(url: root.appendingPathComponent("config.json"))
        let first = Project(name: "original")
        try store.save(Configuration(projects: [first]))
        try store.save(Configuration(projects: [Project(name: "newer")]))
        let damaged = Data("broken json".utf8)
        try damaged.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(store.canRecover)
        let restored = try store.recover(useBackup: true)
        XCTAssertEqual(restored.projects.first?.id, first.id)
        XCTAssertEqual(try store.load()?.projects.first?.id, first.id)
        let preserved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("damaged-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), damaged)
    }

    @MainActor func testUnreadableConfigurationCannotBeOverwrittenUntilExplicitRecovery() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")
        let damaged = Data("{ invalid".utf8)
        try damaged.write(to: url)
        let model = AppModel(configURL: url)
        XCTAssertNotNil(model.configurationError)
        model.addProject(name: "must not overwrite")
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        model.recoverConfiguration(useBackup: false)
        XCTAssertNil(model.configurationError)
        XCTAssertTrue(model.projects.isEmpty)
        model.addProject(name: "recovered")
        XCTAssertEqual(try ConfigurationStore(url: url).load()?.projects.first?.name, "recovered")
    }

    func testLocalHistorySearchFindsOlderTitleLiteralPathAuthorAndReachableHash() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try repository(root)
        let path = "--literal [file].txt"
        try "old\n".write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "--", path], in: root.path)
        _ = try GitClient.text(["commit", "-m", "Needle [literal]"], in: root.path)
        let old = try GitClient.text(["rev-parse", "HEAD"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines)
        for index in 0..<32 { _ = try GitClient.text(["commit", "--allow-empty", "-m", "recent \(index)\n\nNeedle [literal] in body only"], in: root.path) }
        let id = UUID()
        let head = try GitClient.text(["rev-parse", "HEAD"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(try GitClient.commits(in: root.path, repositoryID: id, limit: 30).contains { $0.hash == old })
        XCTAssertEqual(try GitClient.searchCommits(in: root.path, repositoryID: id, head: head, field: .title, query: "needle [literal]", limit: 10).map(\.hash), [old])
        XCTAssertEqual(try GitClient.searchCommits(in: root.path, repositoryID: id, head: head, field: .path, query: path, limit: 10).map(\.hash), [old])
        XCTAssertEqual(try GitClient.searchCommits(in: root.path, repositoryID: id, head: head, field: .author, query: "search tester", limit: 5).count, 5)
        XCTAssertEqual(try GitClient.searchCommits(in: root.path, repositoryID: id, head: head, field: .hash, query: String(old.prefix(8)), limit: 10).map(\.hash), [old])
        XCTAssertThrowsError(try GitClient.searchCommits(in: root.path, repositoryID: id, head: head, field: .hash, query: "--all", limit: 10))
        _ = try GitClient.text(["checkout", "--orphan", "unrelated"], in: root.path)
        _ = try GitClient.text(["commit", "-m", "unrelated root"], in: root.path)
        let unrelated = try GitClient.text(["rev-parse", "HEAD"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertThrowsError(try GitClient.searchCommits(in: root.path, repositoryID: id, head: unrelated, field: .hash, query: old, limit: 10))
        let full = try GitClient.commits(in: root.path, repositoryID: id, limit: 60, revision: head)
        let pages = try GitClient.commits(in: root.path, repositoryID: id, limit: 30, revision: head) + GitClient.commits(in: root.path, repositoryID: id, limit: 30, revision: head, skip: 30)
        XCTAssertEqual(full, pages)
    }

    @MainActor func testDiffSearchMatchesBothSidesWrapsAndNavigatesVirtualRows() async throws {
        let patch = "--- a/file\n+++ b/file\n@@ -1,1 +1,1 @@\n-before needle\n+after needle\n@@ -1000,1 +1000,1 @@\n-last\n+final needle\n"
        let diff = SplitDiff.parse(patch)
        let search = DiffSearch()
        search.prepare(diff)
        search.query = "NEEDLE"
        let deadline = Date().addingTimeInterval(3)
        while search.isSearching, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(search.isSearching)
        XCTAssertEqual(search.matches.count, 2, "A replacement matching both sides counts once per row")
        let first = search.targetRow
        search.move(-1)
        XCTAssertEqual(search.targetRow, search.matches.last)
        search.move(1)
        XCTAssertEqual(search.targetRow, first)
        search.moveHunk(1)
        XCTAssertEqual(diff.rows.first { $0.id == search.targetRow }?.old?.kind, .hunk)
        search.query = "missing"
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertNil(search.targetRow)

        let rows = (0..<10_000).map { DiffRow(id: $0, old: nil, new: DiffLine(number: $0 + 1, text: "row \($0)", kind: .added)) }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = VirtualizedDiffDocumentView(lines: \.new)
        scroll.documentView = document
        document.setContent(rows: rows, width: 600)
        document.showSearch(matches: [9_500], selected: 9_500, navigate: true)
        XCTAssertTrue(document.renderedRowRange.contains(9_500))
        XCTAssertLessThan(document.renderedRowRange.count, 50)
    }

    @MainActor func testEmptyHistoryAndFailedDetailHaveDistinctStatesAndRetryWorks() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try repository(checkout)
        let group = WorktreeGroup(name: "主目录", isPrimary: true)
        let repository = Repository(name: "test", path: checkout.path, groupID: UUID())
        var project = Project(name: "Test")
        project.repositories = [repository]; project.worktreeGroups = [group]
        let config = root.appendingPathComponent("config.json")
        try ConfigurationStore(url: config).save(Configuration(projects: [project], selectedProjectID: project.id, selectedWorktreeGroupID: group.id))
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        try await waitUntil { !model.isRefreshing }
        XCTAssertTrue(model.commits.isEmpty)
        XCTAssertTrue(model.historyErrors.isEmpty, "An unborn branch is a valid empty history")
        XCTAssertTrue(model.historyExhausted.contains(repository.id))

        _ = try GitClient.text(["commit", "--allow-empty", "-m", "valid commit"], in: checkout.path)
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        let commit = try XCTUnwrap(model.commits.first)
        model.activeTab = 1
        let missing = Commit(repositoryID: repository.id, hash: String(repeating: "f", count: 40), committer: "Test", date: Date(), subject: "missing")
        model.selectCommit(missing)
        try await waitUntil { model.detailStates[1].readError != nil }
        XCTAssertTrue(model.detailStates[1].detail.isEmpty, "Errors must not be rendered as patch text")
        model.selectCommit(commit)
        try await waitUntil { model.detailStates[1].commitPatch != nil }
        XCTAssertNil(model.detailStates[1].readError)

        try (String(repeating: "f", count: 40) + "\n").write(to: checkout.appendingPathComponent(".git/refs/heads/main"), atomically: true, encoding: .utf8)
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        XCTAssertNotNil(model.historyErrors[repository.id])
        try (commit.hash + "\n").write(to: checkout.appendingPathComponent(".git/refs/heads/main"), atomically: true, encoding: .utf8)
        model.refresh(useCachedHistory: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertNil(model.historyErrors[repository.id])
        XCTAssertEqual(model.commits.first?.hash, commit.hash)
    }

    @MainActor func testFilePresentationIsPreparedAndReplacedWithTheSelectedDiff() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appendingPathComponent("checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try repository(checkout)
        try "# original\n".write(to: checkout.appendingPathComponent("old.md"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: checkout.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: checkout.path)
        try "".write(to: checkout.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "new.md"], in: checkout.path)
        let group = WorktreeGroup(name: "Primary", isPrimary: true)
        let repository = Repository(name: "test", path: checkout.path, groupID: UUID())
        var project = Project(name: "Presentation")
        project.repositories = [repository]; project.worktreeGroups = [group]
        let config = root.appendingPathComponent("config.json")
        try ConfigurationStore(url: config).save(Configuration(projects: [project], selectedProjectID: project.id, selectedWorktreeGroupID: group.id))
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        try await waitUntil { !model.isRefreshing }
        model.selectFile(try XCTUnwrap(model.snapshots.first?.files.first))
        let state = model.detailStates[0]
        try await waitUntil { state.filePresentation.hasSummary }
        XCTAssertNil(state.filePresentation.oldPath)
        try "# original\nextra\n".write(to: checkout.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        model.selectFile(try XCTUnwrap(model.snapshots.first?.files.first))
        try await waitUntil { state.detail.contains("+extra") }
        XCTAssertNil(state.filePresentation.oldPath)
        XCTAssertFalse(state.filePresentation.hasSummary)
        XCTAssertTrue(state.splitDiff.hasChanges)
    }

    func testFileFiltersKeepPartiallyStagedChangesInBothScopes() {
        let id = UUID()
        let partial = ChangedFile(repositoryID: id, path: "src/File.swift", indexStatus: "M", worktreeStatus: "M", isUntracked: false)
        let new = ChangedFile(repositoryID: id, path: "new.txt", indexStatus: "?", worktreeStatus: "?", isUntracked: true)
        let conflict = ChangedFile(repositoryID: id, path: "conflict.txt", indexStatus: "U", worktreeStatus: "U", isUntracked: false)
        XCTAssertTrue(FileChangeFilter.staged.includes(partial))
        XCTAssertTrue(FileChangeFilter.unstaged.includes(partial))
        XCTAssertTrue(FileChangeFilter.added.includes(new))
        XCTAssertFalse(FileChangeFilter.staged.includes(new))
        XCTAssertTrue(FileChangeFilter.conflict.includes(conflict))
        XCTAssertFalse(FileChangeFilter.modified.includes(conflict))
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate())
    }

    func testReadDeadlineDoesNotWaitForHelpersHoldingOutputPipe() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = GitReadSession(timeout: 0.1)
        let start = Date()
        XCTAssertThrowsError(try GitClient.$readSession.withValue(session) {
            try GitClient.run(["-c", "alias.slow=!sleep 5", "slow"], in: root.path)
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("-c"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testReadDeadlineStopsProcessAndDoesNotCancelLaterReads() throws {
        let session = GitReadSession(timeout: 0.1)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        let start = Date()
        try session.start(process, command: "slow read")
        process.waitUntilExit()
        XCTAssertTrue(session.didTimeOut(process))
        XCTAssertFalse(session.isCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        session.finish(process)
        XCTAssertFalse(session.didTimeOut(process))
        XCTAssertTrue(try GitClient.$readSession.withValue(session) { try GitClient.text(["--version"], in: "/tmp") }.hasPrefix("git version"))
    }
}
