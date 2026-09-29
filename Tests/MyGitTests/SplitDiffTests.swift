import XCTest
@testable import MyGit

final class SplitDiffTests: XCTestCase {
    func testAlignsReplacementsInsertionsAndLaterHunks() {
        let patch = """
        diff --git a/file.txt b/file.txt
        --- a/file.txt
        +++ b/file.txt
        @@ -2,4 +2,5 @@
         same
        -old A
        -old B
        +new A
        +new B
        +new C
         after
        @@ -20,1 +21,1 @@
        -last old
        +last new
        """
        let diff = SplitDiff.parse(patch)
        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.rows.compactMap(\.old?.number), [2, 3, 4, 5, 20])
        XCTAssertEqual(diff.rows.compactMap(\.new?.number), [2, 3, 4, 5, 6, 21])
        XCTAssertEqual(diff.rows.first(where: { $0.new?.text == "new C" })?.old?.text, nil)
        XCTAssertEqual(diff.rows.first(where: { $0.old?.text == "old A" })?.new?.text, "new A")
    }

    func testParsesUntrackedPreviewAndRejectsStatusMessage() {
        let preview = "--- /dev/null\n+++ b/new.txt\n+first\n+second\n"
        let diff = SplitDiff.parse(preview)
        XCTAssertTrue(diff.hasChanges)
        XCTAssertEqual(diff.rows.compactMap(\.new?.number), [1, 2])
        XCTAssertFalse(SplitDiff.parse("这一视图没有可显示的修改。").hasChanges)
    }

    func testKeepsMultipleFilesSeparate() {
        let patch = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/b.txt b/b.txt
        --- a/b.txt
        +++ b/b.txt
        @@ -4 +4 @@
        -before
        +after
        """
        let diff = SplitDiff.parse(patch)
        XCTAssertEqual(diff.rows.compactMap(\.old?.number), [1, 4])
        XCTAssertEqual(diff.rows.compactMap(\.new?.number), [1, 4])
    }
}
