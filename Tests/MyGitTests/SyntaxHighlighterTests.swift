import SwiftUI
import XCTest
@testable import MyGit

final class SyntaxHighlighterTests: XCTestCase {
    private func fragments(_ text: String, _ tokens: [SyntaxToken], kind: SyntaxKind) -> [String] {
        tokens.filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
    }

    func testJavaStringsCommentsAndIdentifiersKeepTheirBoundaries() {
        var lexer = SyntaxHighlighter(path: "Photo.java")
        let text = #"if (photoType == HDR_1X3) { String 中文 = "😀 // if \"quoted\""; // 注释 return 123"#
        let tokens = lexer.tokens(in: text)
        XCTAssertEqual(fragments(text, tokens, kind: .keyword), ["if"])
        XCTAssertEqual(fragments(text, tokens, kind: .number), [])
        XCTAssertEqual(fragments(text, tokens, kind: .comment), ["// 注释 return 123"])
        XCTAssertEqual(fragments(text, tokens, kind: .string), [#""😀 // if \"quoted\"""#])
        XCTAssertEqual(String(SyntaxHighlighter.attributed(text, tokens: tokens).characters), text)
        XCTAssertTrue(tokens.allSatisfy { Range($0.range, in: text) != nil })
    }

    func testMultilineCommentsAndTripleQuotedStrings() {
        var lexer = SyntaxHighlighter(path: "View.swift")
        let start = "/* let ignored = 42"
        XCTAssertEqual(fragments(start, lexer.tokens(in: start), kind: .comment), [start])
        let end = "still comment */ let value = 42"
        let tokens = lexer.tokens(in: end)
        XCTAssertEqual(fragments(end, tokens, kind: .comment), ["still comment */"])
        XCTAssertEqual(fragments(end, tokens, kind: .keyword), ["let"])
        XCTAssertEqual(fragments(end, tokens, kind: .number), ["42"])
        _ = lexer.tokens(in: "let text = \"\"\"")
        let stringLine = "// let this stay a string"
        XCTAssertEqual(fragments(stringLine, lexer.tokens(in: stringLine), kind: .string), [stringLine])
        let closing = "\"\"\"; return text"
        XCTAssertEqual(fragments(closing, lexer.tokens(in: closing), kind: .keyword), ["return"])
    }

    func testMarkupAndUnknownFiles() {
        var lexer = SyntaxHighlighter(path: #""b/\344\270\255.xml""#)
        let text = #"<meta-data android:name="http://example.invalid" android:value="false" />"#
        let tokens = lexer.tokens(in: text)
        XCTAssertEqual(fragments(text, tokens, kind: .string), [#""http://example.invalid""#, #""false""#])
        XCTAssertTrue(fragments(text, tokens, kind: .comment).isEmpty)
        let comment = "<!-- <meta-data"
        XCTAssertEqual(fragments(comment, lexer.tokens(in: comment), kind: .comment), [comment])
        let closing = "android:name=\"x\" -->"
        XCTAssertEqual(fragments(closing, lexer.tokens(in: closing), kind: .comment), [closing])
        var plain = SyntaxHighlighter(path: "notes.txt")
        XCTAssertTrue(plain.tokens(in: "return 123 // text").isEmpty)
    }

    func testDiffMaintainsSeparateStatesAndResetsAtHunkGaps() throws {
        let patch = """
        --- a/Test.java
        +++ b/Test.java
        @@ -1,3 +1,3 @@
        -/* old comment
        +int value = 10;
         return value;
        -*/
        +return 20;
        @@ -30 +30 @@
        -return 30;
        +return 40;
        """
        let diff = SplitDiff.parse(patch)
        let context = try XCTUnwrap(diff.rows.first { $0.old?.number == 2 })
        XCTAssertEqual(context.old?.syntax.first?.kind, .comment)
        XCTAssertEqual(context.new?.syntax.first?.kind, .keyword)
        XCTAssertEqual(diff.rows.last?.old?.syntax.first?.kind, .keyword)
        XCTAssertEqual(diff.rows.last?.new?.syntax.first?.kind, .keyword)
        let highlighted = SyntaxHighlighter.patch(patch)
        XCTAssertEqual(String(highlighted.characters), patch)
        XCTAssertTrue(highlighted.runs.contains { $0.foregroundColor == SyntaxKind.keyword.color })
        XCTAssertTrue(highlighted.runs.contains { $0.backgroundColor != nil })
    }

    @MainActor func testHighlightedLargeDiffStillRendersOnlyVisibleRows() {
        let patch = "--- /dev/null\n+++ b/Test.java\n@@ -0,0 +1,10000 @@\n"
            + (0..<10_000).map { "+int value\($0) = \($0);\n" }.joined()
        let diff = SplitDiff.parse(patch)
        XCTAssertFalse(diff.rows.last?.new?.syntax.isEmpty ?? true)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))
        let document = VirtualizedDiffDocumentView(lines: \.new)
        scroll.documentView = document
        document.setContent(rows: diff.rows, width: 1200, contentID: diff.contentID)
        XCTAssertLessThan(document.renderedRowRange.count, 50)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - 420))
        document.updateVisibleRows()
        XCTAssertEqual(document.renderedRowRange.upperBound, diff.rows.count)
        XCTAssertLessThan(document.renderedRowRange.count, 50)
    }
}
