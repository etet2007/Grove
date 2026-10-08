import AppKit
import XCTest
@testable import MyGit

private actor ConcurrencyProbe {
    var active = 0
    var maximum = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}

final class PerformanceTests: XCTestCase {
    private func repository(at path: URL) throws {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        _ = try GitClient.text(["init", "-b", "main"], in: path.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: path.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: path.path)
        try "initial\n".write(to: path.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: path.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: path.path)
    }

    func testStatusSkipsUnusedStatsAndDoesNotRewriteIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitStats-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try repository(at: root)
        let index = root.appendingPathComponent(".git/index")
        let before = try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date
        let clean = GitReadSession()
        let files = try GitClient.$readSession.withValue(clean) { try GitClient.changedFiles(in: root.path, repositoryID: UUID()) }
        XCTAssertTrue(files.isEmpty)
        XCTAssertEqual(clean.counts, ["status": 1])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: index.path)[.modificationDate] as? Date, before)

        try "initial\nsecond\n".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let unstaged = GitReadSession()
        let changes = try GitClient.$readSession.withValue(unstaged) { try GitClient.changedFiles(in: root.path, repositoryID: UUID()) }
        XCTAssertEqual(unstaged.counts["diff"], 1)
        XCTAssertEqual(changes.first?.stats?.additions, 1)
        _ = try GitClient.text(["add", "."], in: root.path)
        let staged = GitReadSession()
        _ = try GitClient.$readSession.withValue(staged) { try GitClient.changedFiles(in: root.path, repositoryID: UUID()) }
        XCTAssertEqual(staged.counts["diff"], 1)
        print("PERF status: clean 3 → 1 commands; one-sided edits 3 → 2 commands")
    }

    func testBoundedReadsKeepOrderAndLimitConcurrency() async throws {
        let probe = ConcurrencyProbe()
        let results = await boundedConcurrentMap(Array(0..<9)) { value in
            await probe.enter()
            try? await Task.sleep(for: .milliseconds(30 + (9 - value) * 5))
            await probe.leave()
            return value
        }
        XCTAssertEqual(results, Array(0..<9))
        let maximum = await probe.maximum
        XCTAssertEqual(maximum, 3)
    }

    func testParallelGitReadBenchmark() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitParallel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = (0..<6).map { root.appendingPathComponent("repo\($0)") }
        for path in paths {
            try repository(at: path)
            try String(repeating: "new line\n", count: 5_000).write(to: path.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        }
        @Sendable func read(_ path: URL) throws -> Int {
            _ = try GitClient.worktrees(in: path.path)
            let files = try GitClient.changedFiles(in: path.path, repositoryID: UUID())
            _ = try GitClient.commits(in: path.path, repositoryID: UUID(), limit: 30)
            return files.count
        }
        // Warm both code paths, then compare the same local Git workload.
        _ = try paths.map(read)
        var serialSamples: [Double] = []
        var parallelSamples: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            let sequential = try paths.map(read)
            serialSamples.append(Date().timeIntervalSince(start))
            let parallelStart = Date()
            let concurrent = await boundedConcurrentMap(paths) { try? read($0) }
            parallelSamples.append(Date().timeIntervalSince(parallelStart))
            XCTAssertEqual(concurrent.compactMap { $0 }, sequential)
        }
        print(String(format: "PERF six repositories (median of 3): serial %.3f s → bounded parallel %.3f s", serialSamples.sorted()[1], parallelSamples.sorted()[1]))
    }

    @MainActor func testLargeDiffReusesPreparedRowsAndWidth() {
        let text = "--- a/file\n+++ b/file\n@@ -1,10000 +1,10000 @@\n" +
            (0..<10_000).map { "-old \($0)\n+新 line \($0)" }.joined(separator: "\n")
        let start = Date()
        var width: CGFloat = 0
        // Previous view update work: parse and scan all text again.
        for _ in 0..<10 {
            let parsed = SplitDiff.parse(text)
            width = parsed.estimatedContentWidth
        }
        let oldSeconds = Date().timeIntervalSince(start)
        let diff = SplitDiff.parse(text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))
        let document = VirtualizedDiffDocumentView(lines: \.old)
        scroll.documentView = document
        document.setContent(rows: diff.rows, width: width, contentID: diff.contentID)
        let preparedStart = Date()
        for _ in 0..<10 {
            width = diff.estimatedContentWidth
            document.setContent(rows: diff.rows, width: width, contentID: diff.contentID)
        }
        let preparedSeconds = Date().timeIntervalSince(preparedStart)
        XCTAssertEqual(diff.rows.count, 10_002)
        XCTAssertLessThan(document.renderedRowRange.count, 50)
        XCTAssertEqual(width, diff.estimatedContentWidth)
        print(String(format: "PERF 10000-line diff, 10 updates: parse/scan %.3f s → prepared updates %.6f s", oldSeconds, preparedSeconds))
    }

    func testCancellationTerminatesRunningProcessAndPreventsNewReads() throws {
        let session = GitReadSession()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try session.start(process, command: "sleep")
        let start = Date()
        session.cancel()
        process.waitUntilExit()
        session.finish(process)
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertThrowsError(try GitClient.$readSession.withValue(session) {
            try GitClient.text(["--version"], in: FileManager.default.temporaryDirectory.path)
        })
        XCTAssertNil(session.counts["--version"])
        print(String(format: "PERF cancelled 5-second process: stopped after %.3f s", Date().timeIntervalSince(start)))
    }

    @MainActor func testFilesystemEventsRefreshContentAndHiddenDetailOnReturn() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MyGitEvents-\(UUID())")
        let checkout = root.appendingPathComponent("main")
        defer { try? FileManager.default.removeItem(at: root) }
        try repository(at: checkout)
        let group = WorktreeGroup(name: "主目录", isPrimary: true)
        var project = Project(name: "Events")
        project.repositories = [Repository(name: "main", path: checkout.path, groupID: UUID())]
        project.worktreeGroups = [group]
        let config = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id, selectedWorktreeGroupID: group.id)).write(to: config)
        let model = AppModel(configURL: config)
        try await waitUntil { !model.isRefreshing }
        // Flush startup events and then verify idle ticks issue no reads.
        try await Task.sleep(for: .milliseconds(1_000))
        try await waitUntil { !model.isRefreshing }
        let idleCount = model.completedRefreshCount
        for _ in 0..<5 { model.automaticRefresh() }
        XCTAssertEqual(model.completedRefreshCount, idleCount)
        XCTAssertFalse(model.isRefreshing)

        let editStart = Date()
        try "initial\nfirst change\n".write(to: checkout.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await waitUntil { !model.isRefreshing && model.snapshots.first?.files.count == 1 }
        print(String(format: "PERF filesystem save → file list: %.3f s", Date().timeIntervalSince(editStart)))
        model.selectFile(try XCTUnwrap(model.snapshots.first?.files.first))
        try await waitUntil { model.detailStates[0].detail.contains("+first change") }
        let session = model.detailStates[0].readSession
        model.activeTab = 1
        let count = model.completedRefreshCount
        try "initial\nother change\n".write(to: checkout.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await waitUntil { model.completedRefreshCount > count && !model.isRefreshing }
        XCTAssertTrue(model.detailStates[0].readSession === session)
        XCTAssertTrue(model.detailStates[0].detail.contains("+first change"))
        model.activeTab = 0
        try await waitUntil { model.detailStates[0].detail.contains("+other change") }
        XCTAssertFalse(model.detailStates[0].readSession === session)

        // Metadata events must invalidate the HEAD-keyed history.
        _ = try GitClient.text(["add", "."], in: checkout.path)
        _ = try GitClient.text(["commit", "-m", "updated"], in: checkout.path)
        try await waitUntil { !model.isRefreshing && model.commits.first?.subject == "updated" }
        XCTAssertTrue(model.snapshots.first?.files.isEmpty == true)
        _ = try GitClient.text(["remote", "add", "origin", "git@gitlab.example:team/first.git"], in: checkout.path)
        try await waitUntil { model.snapshots.first?.mergeRequestURL?.path == "/team/first/-/merge_requests/new" }
        _ = try GitClient.text(["remote", "set-url", "origin", "git@gitlab.example:team/second.git"], in: checkout.path)
        try await waitUntil { model.snapshots.first?.mergeRequestURL?.path == "/team/second/-/merge_requests/new" }
        model.automaticRefreshEnabled = false
        let backgroundCount = model.completedRefreshCount
        try "background edit\n".write(to: checkout.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(model.completedRefreshCount, backgroundCount)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.snapshots.first?.files.isEmpty == true)
        model.automaticRefreshEnabled = true
        model.automaticRefresh()
        try await waitUntil { !model.isRefreshing && model.snapshots.first?.files.count == 1 }
        let linked = root.appendingPathComponent("linked")
        _ = try GitClient.text(["worktree", "add", "-b", "feature", linked.path], in: checkout.path)
        try await waitUntil { model.selectedProject?.worktreeGroups.contains { $0.branch == "feature" } == true }
        XCTAssertEqual(gitMetadataRoot(in: linked.path), canonicalFilesystemPath(checkout.appendingPathComponent(".git").path))
        let feature = try XCTUnwrap(model.selectedProject?.worktreeGroups.first { $0.branch == "feature" })
        model.selectWorktreeGroup(feature.id)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.snapshots.first?.selected?.path, canonicalFilesystemPath(linked.path))
        _ = try GitClient.text(["worktree", "remove", linked.path], in: checkout.path)
        try await waitUntil { !model.isRefreshing && model.snapshots.first?.selected?.isPrimary == true }
        XCTAssertEqual(model.selectedProject?.repositories.count, 1)
        print("PERF idle ticks: 0 Git commands; hidden detail: 0 reloads; HEAD/remote/worktree invalidation passed")
    }

    @MainActor func testOnlyChangedRepositoryIsReadAndSiblingPathsDoNotMatch() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MyGitPartial-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = (0..<3).map { root.appendingPathComponent("repo\($0)") }
        for path in paths { try repository(at: path) }
        var project = Project(name: "Partial")
        let group = WorktreeGroup(name: "主目录", isPrimary: true)
        project.worktreeGroups = [group]
        project.repositories = paths.map { Repository(name: $0.lastPathComponent, path: $0.path, groupID: UUID()) }
        let config = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id, selectedWorktreeGroupID: group.id)).write(to: config)
        let model = AppModel(configURL: config)
        try await waitUntil { !model.isRefreshing }
        let file = paths[1].appendingPathComponent("file.txt")
        try "changed\n".write(to: file, atomically: true, encoding: .utf8)
        model.refresh(useCachedHistory: true, changedPaths: [file.path])
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.lastRefreshCommandCounts["status"], 1)
        XCTAssertEqual(model.lastRefreshCommandCounts["diff"], 1)
        XCTAssertNil(model.lastRefreshCommandCounts["log"])
        XCTAssertNil(model.lastRefreshCommandCounts["remote"])
        XCTAssertEqual(model.snapshots.map { $0.files.count }, [0, 1, 0])
        XCTAssertFalse(pathIsInside(paths[0].path + "other/file", root: paths[0].path))
        print("PERF partial refresh: 3 repository status reads → 1; cached log/MR reads: 0")
    }

    func testDeletedPathsKeepCanonicalAncestor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitPaths-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        XCTAssertEqual(canonicalFilesystemPath(alias.appendingPathComponent("deleted/file").path),
                       canonicalFilesystemPath(target.path) + "/deleted/file")
    }

    @MainActor private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "Timed out waiting for repository update", file: file, line: line)
    }
}
