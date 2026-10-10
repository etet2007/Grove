import XCTest
@testable import MyGit

final class PatchPresentationTests: XCTestCase {
    private func file(_ body: String) -> CommitFilePatch {
        CommitPatch.parse("diff --git a/file b/file\n" + body).files[0]
    }

    func testMetadataOnlySummariesDoNotHideTextOrUnknownMetadata() {
        XCTAssertEqual(file("new file mode 100644").summaryTitle, "新增空文件")
        XCTAssertEqual(file("deleted file mode 100644").summaryTitle, "空文件已删除")
        let mode = "old mode 100644\nnew mode 100755"
        XCTAssertEqual(file(mode).modeChangeDescription, "文件已增加可执行权限")
        XCTAssertNotNil(file(mode).summaryTitle)
        XCTAssertNil(file(mode + "\n--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new").summaryTitle)
        XCTAssertNil(file("new file mode 100644\nunknown metadata").summaryTitle)
    }

    func testSubmoduleAndSymlinkShowActualVersions() {
        let module = file("index abc..def 160000\n--- a/file\n+++ b/file\n@@ -1 +1 @@\n-Subproject commit abc\n+Subproject commit def-dirty")
        XCTAssertEqual(module.summaryTitle, "子模块版本已更新")
        XCTAssertEqual(module.summaryVersions.map { $0.1 }, ["abc", "def-dirty"])
        let link = file("index abc..def 120000\n--- a/file\n+++ b/file\n@@ -1 +1 @@\n-../old path\n+../new path\n\\ No newline at end of file")
        XCTAssertEqual(link.summaryTitle, "链接目标已修改")
        XCTAssertEqual(link.summaryVersions.map { $0.1 }, ["../old path", "../new path"])
        let conversion = file("old mode 100644\nnew mode 120000\n@@ -1 +1 @@\n-source\n+target")
        XCTAssertNil(conversion.summaryTitle)
    }

    func testNewlineNotePreservesPairedRowsAndDoesNotReplaceCode() {
        let patch = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file"
        let rows = SplitDiff.parse(patch).rows
        let changed = rows.first { $0.old?.kind == .removed }
        XCTAssertEqual(changed?.old?.text, "old")
        XCTAssertEqual(changed?.new?.text, "new")
        XCTAssertEqual(rows.filter { $0.old?.text == AppLocalization.text("文件末尾没有换行符") }.count, 1)
        XCTAssertEqual(PatchPresentation.readableText("+\\ No newline at end of file"), "+\\ No newline at end of file")
    }

    func testUntrackedBinaryAndEmptyFilesHavePaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, data) in [("binary.bin", Data([0, 1, 2])), ("empty.txt", Data())] {
            try data.write(to: directory.appendingPathComponent(name))
            let changed = ChangedFile(repositoryID: UUID(), path: name, indexStatus: "?", worktreeStatus: "?", isUntracked: true)
            let preview = try GitClient.diff(for: changed, in: directory.path, mode: .unstaged)
            XCTAssertTrue(preview.contains(name))
            XCTAssertFalse(preview.contains("@@"))
        }
    }
}
