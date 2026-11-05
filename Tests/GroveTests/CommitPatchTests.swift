import XCTest
@testable import Grove

final class CommitPatchTests: XCTestCase {
    func testBinaryDeletionUsesImageSummaryAndPreservesPath() {
        let path = "containers/ODMLegacyStrings/src/main/res/drawable-xxhdpi/ic_playback_list_free_pano_without_fusion.webp"
        let file = CommitPatch.parse("""
        diff --git a/\(path) b/\(path)
        deleted file mode 100644
        index b9eaded1..00000000
        Binary files a/\(path) and /dev/null differ
        """).files[0]
        XCTAssertEqual(file.path, path)
        XCTAssertEqual(file.change, .deleted)
        XCTAssertEqual(file.binarySummaryTitle, "图片已删除")
        XCTAssertNil(file.oldPath)
    }

    func testBinarySummariesDistinguishChangesAndTextFiles() {
        for (metadata, title) in [
            ("new file mode 100644", "新增二进制文件"),
            ("deleted file mode 100644", "二进制文件已删除"),
            ("index abc..def", "二进制文件已修改"),
            ("rename from old.bin\nrename to new.bin", "二进制文件已移动或重命名"),
            ("copy from old.bin\ncopy to new.bin", "二进制文件已复制")
        ] {
            let file = CommitPatch.parse("diff --git a/old.bin b/new.bin\n" + metadata + "\nGIT binary patch").files[0]
            XCTAssertEqual(file.binarySummaryTitle, title)
            if file.change == .renamed || file.change == .copied {
                XCTAssertEqual(file.oldPath, "old.bin")
                XCTAssertEqual(file.path, "new.bin")
            }
        }
        let textImage = CommitPatch.parse("diff --git a/image.png b/image.png\n@@ -1 +1 @@\n-old\n+new").files[0]
        XCTAssertNil(textImage.binarySummaryTitle)
        let image = CommitPatch.parse("diff --git a/image.PNG b/image.PNG\nBinary files a/image.PNG and b/image.PNG differ").files[0]
        XCTAssertEqual(image.binarySummaryTitle, "图片已修改")
    }

    func testSeparatesFilesAndCountsOnlyHunkContent() {
        let text = """
        commit abc
        diff --git a/dir/removed.kt b/dir/removed.kt
        deleted file mode 100644
        --- a/dir/removed.kt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -one
        -two
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +++not a header
        +two
        diff --git a/image.png b/image.png
        Binary files a/image.png and b/image.png differ
        """
        let patch = CommitPatch.parse(text)
        XCTAssertEqual(patch.files.count, 3)
        XCTAssertEqual(patch.additions, 2)
        XCTAssertEqual(patch.deletions, 2)
        XCTAssertEqual(patch.files[0].change, .deleted)
        XCTAssertEqual(patch.files[0].name, "removed.kt")
        XCTAssertEqual(patch.files[0].directory, "dir")
        XCTAssertFalse(patch.files[0].patch.contains("new.txt"))
        XCTAssertEqual(patch.files[1].change, .added)
        XCTAssertTrue(patch.files[2].isBinary)
    }

    func testRenameModeChangeAndQuotedUTF8Paths() {
        let patch = CommitPatch.parse(#"""
        diff --git a/old name.txt b/new name.txt
        similarity index 100%
        rename from old name.txt
        rename to new name.txt
        diff --git "a/\344\270\255.txt" "b/\344\270\255.txt"
        old mode 100644
        new mode 100755
        """#)
        XCTAssertEqual(patch.files[0].path, "new name.txt")
        XCTAssertEqual(patch.files[0].oldPath, "old name.txt")
        XCTAssertEqual(patch.files[0].change, .renamed)
        XCTAssertTrue(patch.files[0].isPureRename)
        XCTAssertEqual(patch.files[1].path, "中.txt")
        XCTAssertEqual(patch.files[1].change, .modified)
        XCTAssertEqual(patch.additions, 0)
        XCTAssertTrue(CommitPatch.parse("正在读取…").files.isEmpty)
    }

    func testRenameSummaryPreservesOtherChangesAndDecodesPaths() {
        let rename = #"""
        diff --git "a/\344\270\255.txt" "b/archive/\344\270\255.txt"
        similarity index 100%
        rename from "\344\270\255.txt"
        rename to "archive/\344\270\255.txt"
        """#
        let file = CommitPatch.parse(rename).files[0]
        XCTAssertTrue(file.isPureRename)
        XCTAssertEqual(file.oldPath, "中.txt")
        XCTAssertEqual(file.path, "archive/中.txt")
        for extra in ["old mode 100644\nnew mode 100755", "@@ -1 +1 @@\n-old\n+new", "Binary files a/old and b/new differ"] {
            XCTAssertFalse(CommitPatch.parse(rename + "\n" + extra).files[0].isPureRename)
        }
        XCTAssertFalse(CommitPatch.parse(rename.replacingOccurrences(of: "100%", with: "90%")).files[0].isPureRename)
    }
}
