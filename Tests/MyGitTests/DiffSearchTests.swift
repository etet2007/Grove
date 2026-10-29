import AppKit
import XCTest
@testable import MyGit

final class DiffSearchTests: XCTestCase {
    @MainActor func testLatestQueryAndDocumentWinOverPendingWork() async throws {
        let search = DiffSearch()
        search.prepare(text: String(repeating: "old needle\n", count: 50_000))
        search.query = "needle"
        try await Task.sleep(for: .milliseconds(100))
        search.prepare(text: "current document\nnew needle")
        search.query = "new needle"
        try await waitForSearch(search)
        XCTAssertEqual(search.matches, [1])
        XCTAssertEqual(search.matchingRows, [1])
        XCTAssertEqual(search.targetRow, 1)
        XCTAssertEqual(search.displayLines.map(\.text), ["current document", "new needle"])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(search.matches, [1], "Cancelled work must not overwrite the current document's results")
    }

    @MainActor func testClearingQueryCancelsPendingResultsAndAllowsAnotherSearch() async throws {
        let search = DiffSearch()
        search.prepare(text: "needle\nother needle")
        search.query = "needle"
        XCTAssertTrue(search.isSearching)
        search.query = ""
        XCTAssertFalse(search.isSearching)
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertTrue(search.matchingRows.isEmpty)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(search.matches.isEmpty)
        XCTAssertNil(search.targetRow)
        search.query = "other"
        try await waitForSearch(search)
        XCTAssertEqual(search.matches, [1])
    }

    @MainActor func testPatchDisplayLinesAndSearchUseTheSameReadableContent() async throws {
        let search = DiffSearch()
        let raw = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-before\n+after\n\\ No newline at end of file"
        let readable = PatchPresentation.readableText(raw)
        search.prepare(patch: raw)
        search.query = readable.components(separatedBy: "\n").last!
        try await waitForSearch(search)
        XCTAssertEqual(search.displayLines.map(\.text), readable.components(separatedBy: "\n"))
        XCTAssertEqual(search.matches, [5])
        search.moveHunk(1)
        XCTAssertEqual(search.targetRow, 2)
        // A plain source with the same bytes must not reuse the formatted patch index.
        search.prepare(text: raw)
        search.query = "No newline"
        try await waitForSearch(search)
        XCTAssertEqual(search.matches, [5])
        XCTAssertEqual(search.displayLines.last?.text, "\\ No newline at end of file")
    }

    @MainActor private func waitForSearch(_ search: DiffSearch) async throws {
        let deadline = Date().addingTimeInterval(4)
        while search.isSearching, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(search.isSearching, "Timed out waiting for the current query")
    }

    @MainActor func testLargeDiffQuerySchedulingBudget() async throws {
        guard ProcessInfo.processInfo.environment["MYGIT_SEARCH_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MYGIT_SEARCH_BENCHMARK=1 to measure main-thread search input cost")
        }
        let text = (0..<50_000).map { "line \($0): needle value with enough surrounding text to exercise a large diff search" }.joined(separator: "\n")
        let search = DiffSearch()
        search.prepare(text: text)
        try await Task.sleep(for: .milliseconds(250))
        var samples: [Double] = []
        for query in ["needle", "missing", "value", "NEEDLE"] {
            let start = CACurrentMediaTime()
            search.query = query
            samples.append((CACurrentMediaTime() - start) * 1000)
        }
        samples.sort()
        print(String(format: "SEARCH INPUT 50000 lines: median %.3f ms, maximum %.3f ms", samples[samples.count / 2], samples.last!))
        XCTAssertLessThan(samples[samples.count / 2], 2, "Typing must schedule background work instead of scanning the document on the main actor")
    }
}
