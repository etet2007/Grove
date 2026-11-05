import XCTest
import SwiftUI
import WebKit
@testable import Grove

final class MarkdownPreviewTests: XCTestCase {
    func testRichDocumentAndEscaping() {
        let html = MarkdownPreview.body("""
        # 标题

        **重点**、`files/Analytics`、*说明*、~~删除~~、==高亮==

        - [x] 完成
        - 待办
          - 子项

        > 引用

        | 目录 | 状态 |
        | :--- | ---: |
        | `a` | 确认 |

        ```swift
        let text = "<script>"
        ```
        """)
        for fragment in ["<h1 ", "<strong>重点</strong>", "<code>files/Analytics</code>", "<em>说明</em>",
                         "<del>删除</del>", "<mark>高亮</mark>", "disabled checked", "<blockquote>", "<table>",
                         "text-align:right", "&lt;script&gt;", "syntax-keyword"] {
            XCTAssertTrue(html.contains(fragment), fragment)
        }
    }

    func testRepositoryContentCannotInjectHTMLOrLoadResources() {
        let html = MarkdownPreview.body("""
        <script>alert(1)</script>

        <img src="https://example.invalid/tracker">

        [unsafe](javascript:alert(1)) [site](https://example.invalid)
        ![remote](https://example.invalid/image.png)
        ![local](file:///etc/passwd)
        """)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("href=\"javascript:"))
        XCTAssertTrue(html.contains("href=\"https://example.invalid\""))
        XCTAssertTrue(html.contains("image-placeholder"))
        let document = MarkdownPreview.document(body: html, fontSize: 12)
        XCTAssertTrue(document.contains("default-src 'none'"))
        XCTAssertTrue(document.contains("script-src 'none'"))
    }


    @MainActor func testWebKitDisplaysDocumentAndTableWithoutHorizontalPageOverflow() async throws {
        let body = MarkdownPreview.body("""
        # Visox 运行时路径治理：目录与处理方法人工复核表

        更新：2026-10-20。**人工结论尚未填写；本表用于人工复核。**

        ## 阅读口径

        - 方法组 M01–M36 同时列出处置方法和代码入口。
        - **待人工核实**：请补充实际业务状态。
        - external 相对 `/sdcard/Android/data/com.drone.visox/`。
          - 嵌套列表保留层次

        > 引用内容，保留原文与上下文。

        | 目录 | 业务状态 | 备注 |
        | :--- | :--- | :--- |
        | `files/Analytics` | **待核实** | 一段较长的目录说明 |

        ```swift
        let checkout = "working tree"
        ```
        """)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MarkdownWebView(html: MarkdownPreview.document(body: body, fontSize: 12)))
        window.orderFront(nil)
        defer { window.close() }
        func findWebView(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap { findWebView($0) }.first
        }
        var loaded: WKWebView?
        for _ in 0..<200 {
            if let web = findWebView(try XCTUnwrap(window.contentView)), !web.isLoading,
               let heading = try? await web.evaluateJavaScript("document.querySelector('h1')?.textContent"), heading is String {
                loaded = web
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let web = try XCTUnwrap(loaded)
        let tables = try await web.evaluateJavaScript("document.querySelectorAll('table').length") as? Int
        XCTAssertEqual(tables, 1)
        let overflow = try await web.evaluateJavaScript("document.documentElement.scrollWidth > innerWidth") as? Bool
        XCTAssertEqual(overflow, false)
        if let output = ProcessInfo.processInfo.environment["GROVE_MARKDOWN_SNAPSHOT"] {
            let image = try await web.takeSnapshot(configuration: nil)
            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: output))
        }
    }

    func testVersionsRespectIndexWorktreeAndHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveMarkdown-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String { try GitClient.text(args, in: root.path) }
        func write(_ text: String, path: String = "note.md") throws {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Test"])
        _ = try git(["config", "user.email", "test@example.invalid"])
        try write("# HEAD\n\nEntire unchanged paragraph\n")
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "base"])
        try write("# Index\n\nEntire unchanged paragraph\n")
        _ = try git(["add", "."])
        try write("# Working\n\nEntire unchanged paragraph\n")
        let before = try git(["status", "--porcelain=v1"])
        let unstaged = GitClient.markdownVersions(path: "note.md", in: root.path)
        XCTAssertTrue(try XCTUnwrap(unstaged.old.body).contains("Index"))
        XCTAssertTrue(try XCTUnwrap(unstaged.new.body).contains("Working"))
        XCTAssertTrue(try XCTUnwrap(unstaged.new.body).contains("Entire unchanged paragraph"))
        let staged = GitClient.markdownVersions(path: "note.md", in: root.path, mode: .staged)
        XCTAssertTrue(try XCTUnwrap(staged.old.body).contains("HEAD"))
        XCTAssertTrue(try XCTUnwrap(staged.new.body).contains("Index"))
        let all = GitClient.markdownVersions(path: "note.md", in: root.path, mode: .all)
        XCTAssertTrue(try XCTUnwrap(all.old.body).contains("HEAD"))
        XCTAssertTrue(try XCTUnwrap(all.new.body).contains("Working"))
        XCTAssertEqual(before, try git(["status", "--porcelain=v1"]))
        _ = try git(["commit", "-m", "index"])
        let hash = try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let history = GitClient.markdownVersions(path: "note.md", in: root.path, commit: hash)
        XCTAssertTrue(try XCTUnwrap(history.old.body).contains("HEAD"))
        XCTAssertTrue(try XCTUnwrap(history.new.body).contains("Index"))
        _ = try git(["mv", "note.md", "renamed.md"])
        _ = try git(["commit", "-m", "rename"])
        let renamed = GitClient.markdownVersions(path: "renamed.md", oldPath: "note.md", in: root.path, commit: "HEAD")
        XCTAssertTrue(try XCTUnwrap(renamed.old.body).contains("Index"))
        XCTAssertTrue(try XCTUnwrap(renamed.new.body).contains("Index"))
        try write("", path: "empty.md")
        let empty = GitClient.markdownVersions(path: "empty.md", in: root.path, untracked: true)
        XCTAssertNil(empty.old.body)
        XCTAssertEqual(empty.new.body, "")
        let untrackedStaged = GitClient.markdownVersions(path: "empty.md", in: root.path, mode: .staged, untracked: true)
        XCTAssertNil(untrackedStaged.new.body)
        try Data([0xff, 0x00]).write(to: root.appendingPathComponent("binary.md"))
        XCTAssertNil(GitClient.markdownVersions(path: "binary.md", in: root.path, untracked: true).new.body)
    }
}
