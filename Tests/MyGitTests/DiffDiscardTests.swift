import XCTest
@testable import MyGit

final class DiffDiscardTests: XCTestCase {
    private func fixture(contents: String = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitDiscard-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        try contents.write(to: root.appendingPathComponent("文件 with spaces.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: root.path)
        return root
    }

    private func request(_ root: URL, name: String = "文件 with spaces.txt", select: (DiffRow) -> Bool) throws -> DiffDiscardRequest {
        let file = try XCTUnwrap(GitClient.changedFiles(in: root.path, repositoryID: UUID()).first { $0.path == name })
        let patch = try GitClient.diff(for: file, in: root.path, mode: .unstaged)
        let selected = Set(SplitDiff.parse(patch).rows.filter(select).map(\.id))
        return DiffDiscardRequest(file: file, checkoutPath: root.path, patch: patch, selectedRows: selected)
    }

    func testDiscardOneReplacementKeepsOtherRowsAndIndexExactly() throws {
        let root = try fixture(contents: "A\nB\nC\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try "A\nSTAGED\nC\n".write(to: target, atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        let index = try GitClient.run(["show", ":文件 with spaces.txt"], in: root.path)
        try "X\nY\nZ\nextra\n".write(to: target, atomically: true, encoding: .utf8)
        let selection = try request(root) { $0.new?.text == "Y" }
        try DiffDiscard.apply(selection)
        XCTAssertEqual(try String(contentsOf: target), "X\nSTAGED\nZ\nextra\n")
        XCTAssertEqual(try GitClient.run(["show", ":文件 with spaces.txt"], in: root.path), index)
        XCTAssertEqual(try GitClient.text(["diff", "--cached", "--numstat"], in: root.path).split(separator: "\t").first, "1")
    }

    func testDiscardOneHunkKeepsLaterHunkAndExecutableMode() throws {
        let lines = (1...30).map { "line \($0)\n" }.joined()
        let root = try fixture(contents: lines)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        let updated = lines.replacingOccurrences(of: "line 2\n", with: "changed early\nextra early\n")
            .replacingOccurrences(of: "line 28\n", with: "changed late\n")
        try updated.write(to: target, atomically: true, encoding: .utf8)
        let selection = try request(root) { ($0.new?.number ?? Int.max) < 8 && $0.new?.kind == .added }
        try DiffDiscard.apply(selection)
        XCTAssertEqual(try String(contentsOf: target), lines.replacingOccurrences(of: "line 28\n", with: "changed late\n"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testPureDeletionsAndUnequalReplacementLengths() throws {
        let root = try fixture(contents: "A\nB\nC\nD\nE\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try "X\nD\nE\n".write(to: target, atomically: true, encoding: .utf8)
        try DiffDiscard.apply(request(root) { $0.old?.text == "B" })
        XCTAssertEqual(try String(contentsOf: target), "X\nB\nD\nE\n")
        // Restoring another removed line uses the newly loaded diff's positions.
        try DiffDiscard.apply(request(root) { $0.old?.text == "C" })
        XCTAssertEqual(try String(contentsOf: target), "X\nB\nC\nD\nE\n")
    }

    func testDeletedFileCanRestoreOnlySelectedLines() throws {
        let root = try fixture(contents: "A\nB\nC\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try FileManager.default.removeItem(at: target)
        try DiffDiscard.apply(request(root) { $0.old?.text == "B" })
        XCTAssertEqual(try String(contentsOf: target), "B\n")
    }

    func testUntrackedLinesAreRemovedWithoutDeletingTheFile() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("new.txt")
        try "keep\ndiscard\nlast".write(to: target, atomically: true, encoding: .utf8)
        try DiffDiscard.apply(request(root, name: "new.txt") { $0.new?.text == "discard" })
        XCTAssertEqual(try String(contentsOf: target), "keep\nlast")
        try DiffDiscard.apply(request(root, name: "new.txt") { $0.new?.kind == .added })
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: target), Data())
    }

    func testStaleWorktreeAndIndexRejectWithoutWriting() throws {
        let root = try fixture(contents: "original\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try "changed\n".write(to: target, atomically: true, encoding: .utf8)
        let selection = try request(root) { $0.new?.kind == .added }
        try "newer edits\n".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try DiffDiscard.apply(selection))
        XCTAssertEqual(try String(contentsOf: target), "newer edits\n")
        try "changed\n".write(to: target, atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        XCTAssertThrowsError(try DiffDiscard.apply(selection))
        XCTAssertEqual(try String(contentsOf: target), "changed\n")
    }

    func testCRLFAndMissingFinalNewlineArePreserved() throws {
        let root = try fixture(contents: "A\r\nB\r\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try "X\r\nY\r\nextra\r\n".write(to: target, atomically: true, encoding: .utf8)
        try DiffDiscard.apply(request(root) { $0.new?.text == "Y\r" || $0.new?.text == "Y" })
        XCTAssertEqual(try Data(contentsOf: target), Data("X\r\nB\r\nextra\r\n".utf8))
        let eofRoot = try fixture(contents: "original")
        defer { try? FileManager.default.removeItem(at: eofRoot) }
        let eofTarget = eofRoot.appendingPathComponent("文件 with spaces.txt")
        try "changed\n".write(to: eofTarget, atomically: true, encoding: .utf8)
        try DiffDiscard.apply(request(eofRoot) { $0.new?.kind == .added })
        XCTAssertEqual(try Data(contentsOf: eofTarget), Data("original".utf8))
    }

    func testSymlinkAndContentFilterAreRejected() throws {
        let root = try fixture(contents: "A\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        let outside = root.appendingPathComponent("outside.txt")
        try "X\n".write(to: target, atomically: true, encoding: .utf8)
        let selection = try request(root) { $0.new?.kind == .added }
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        XCTAssertThrowsError(try DiffDiscard.apply(selection))
        XCTAssertEqual(try String(contentsOf: outside), "outside\n")
        try FileManager.default.removeItem(at: target)
        try "X\n".write(to: target, atomically: true, encoding: .utf8)
        try "* filter=custom\n".write(to: root.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try DiffDiscard.apply(selection))
        XCTAssertEqual(try String(contentsOf: target), "X\n")
    }

    @MainActor func testContextMenuTargetsChangedRowAndContainingHunk() {
        let diff = SplitDiff.parse("--- a/file\n+++ b/file\n@@ -1,3 +1,3 @@\n-A\n-B\n+X\n+Y\n context\n@@ -10 +10 @@\n-C\n+Z\n")
        let targets = DiffDiscardTargets()
        targets.prepare(diff)
        let changed = diff.rows.first { $0.new?.text == "X" }!.id
        let context = diff.rows.first { $0.new?.kind == .context }!.id
        XCTAssertEqual(targets.lineTargets(for: changed), [changed])
        XCTAssertEqual(targets.hunkTargets(for: changed).count, 2)
        XCTAssertEqual(targets.hunkTargets(for: context), targets.hunkTargets(for: changed))
        XCTAssertTrue(targets.lineTargets(for: context).isEmpty)
        let document = VirtualizedDiffDocumentView(lines: \.new)
        var requested: Set<Int> = []
        document.setContent(rows: diff.rows, width: 600, fontScale: 1.5, contentID: diff.contentID,
                            discardTargets: targets) { rows, contentID in
            requested = rows
            XCTAssertEqual(contentID, diff.contentID)
        }
        let menu = document.discardMenu(at: NSPoint(x: 100, y: CGFloat(changed) * 31.5 + 10))!
        XCTAssertEqual(menu.items.count, 2)
        let item = menu.items[0]
        _ = (item.target as? NSObject)?.perform(item.action!)
        XCTAssertEqual(requested, [changed])
        let block = menu.items[1]
        _ = (block.target as? NSObject)?.perform(block.action!)
        XCTAssertEqual(requested, targets.hunkTargets(for: changed))
        XCTAssertEqual(document.discardMenu(at: NSPoint(x: 100, y: CGFloat(context) * 31.5 + 10))?.items.count, 1)
        XCTAssertNil(document.discardMenu(at: NSPoint(x: 100, y: 1)))
        requested = []
        document.setContent(rows: diff.rows, width: 600, contentID: UUID())
        _ = (item.target as? NSObject)?.perform(item.action!)
        XCTAssertTrue(requested.isEmpty, "An old menu must not act on a refreshed diff")
    }

    @MainActor func testModelRefreshesAfterDiscardAndKeepsStagedContent() async throws {
        let root = try fixture(contents: "original\n")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 with spaces.txt")
        try "staged\n".write(to: target, atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        try "unstaged\n".write(to: target, atomically: true, encoding: .utf8)
        let group = WorktreeGroup(name: "Primary", isPrimary: true)
        let repository = Repository(name: "Test", path: root.path, groupID: UUID())
        let project = Project(name: "Test", repositories: [repository], worktreeGroups: [group])
        let config = root.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id,
                                               selectedWorktreeGroupID: group.id)).write(to: config)
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        let deadline = Date().addingTimeInterval(10)
        while model.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
        let file = try XCTUnwrap(model.snapshots.first?.files.first { $0.path == "文件 with spaces.txt" })
        model.selectFile(file)
        while !model.detailStates[0].splitDiff.hasChanges && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let state = model.detailStates[0]
        XCTAssertTrue(state.splitDiff.hasChanges)
        let selected = Set(state.splitDiff.rows.filter { $0.new?.kind == .added }.map(\.id))
        await model.discard(DiffDiscardRequest(file: file, checkoutPath: root.path, patch: state.detail, selectedRows: selected))
        while model.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isDiscarding)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.error)
        XCTAssertEqual(try String(contentsOf: target), "staged\n")
        let refreshed = try XCTUnwrap(model.snapshots.first?.files.first { $0.path == file.path })
        XCTAssertTrue(refreshed.hasStaged)
        XCTAssertFalse(refreshed.hasUnstaged)
        XCTAssertEqual(model.selectedWorktreeGroupID, group.id)
        while state.splitDiff.hasChanges && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(state.splitDiff.hasChanges)
    }
}
