import XCTest
@testable import MyGit

final class PatchPresentationTests: XCTestCase {
    func testPreparedSummaryKeepsMixedPatchSectionsAndReadableText() throws {
        let text = "Commit message\ndiff --git a/empty b/empty\nnew file mode 100644\ndiff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file"
        let result = try XCTUnwrap(PreparedPatchSummary.prepare(text))
        XCTAssertEqual(result.sections.count, 3)
        guard case .text(let preamble) = result.sections[0],
              case .summary(let summary) = result.sections[1],
              case .text(let patch) = result.sections[2] else {
            return XCTFail("Expected preamble, summary and text patch")
        }
        XCTAssertEqual(preamble, "Commit message")
        XCTAssertEqual(summary.title, "新增空文件")
        XCTAssertEqual(summary.path, "empty")
        XCTAssertTrue(patch.contains("+new"))
        XCTAssertTrue(patch.contains(AppLocalization.text("文件末尾没有换行符")))
        let plain = try XCTUnwrap(PreparedPatchSummary.prepare("plain text"))
        guard case .text(let value) = try XCTUnwrap(plain.sections.first) else { return XCTFail("Expected text") }
        XCTAssertEqual(value, "plain text")
    }

    @MainActor func testPreparedFilePresentationPreservesRenameAndSummaryDecisionsAndClearsWithDetail() {
        let rename = "diff --git a/old.md b/new.md\nsimilarity index 100%\nrename from old.md\nrename to new.md"
        let metadata = FileDiffPresentation.prepare(rename)
        XCTAssertEqual(metadata.oldPath, "old.md")
        XCTAssertTrue(metadata.hasSummary)
        let text = "diff --git a/file b/file\n--- a/file\n+++ b/file\n@@ -1 +1 @@\n-before\n+after"
        XCTAssertFalse(FileDiffPresentation.prepare(text).hasSummary)
        XCTAssertTrue(FileDiffPresentation.prepare("diff --git a/file b/file\nnew file mode 100644").hasSummary)
        XCTAssertTrue(FileDiffPresentation.prepare("diff --git a/file b/file\nBinary files a/file and b/file differ").hasSummary)
        let state = DetailState()
        state.filePresentation = metadata
        state.clear()
        XCTAssertNil(state.filePresentation.oldPath)
        XCTAssertFalse(state.filePresentation.hasSummary)
    }

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
