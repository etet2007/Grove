import XCTest
@testable import MyGit

final class CommitPatchTests: XCTestCase {
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
        XCTAssertEqual(patch.files[1].path, "中.txt")
        XCTAssertEqual(patch.files[1].change, .modified)
        XCTAssertEqual(patch.additions, 0)
        XCTAssertTrue(CommitPatch.parse("正在读取…").files.isEmpty)
    }
}
