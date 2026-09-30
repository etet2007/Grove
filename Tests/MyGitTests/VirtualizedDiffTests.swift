import AppKit
import XCTest
@testable import MyGit

final class VirtualizedDiffTests: XCTestCase {
    @MainActor func testLargeDiffHostsOnlyViewportAndFollowsScrollToEnd() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))
        let document = VirtualizedDiffDocumentView(lines: \.old)
        scroll.documentView = document
        let rows = (0..<10_000).map { index in
            DiffRow(id: index, old: DiffLine(number: index + 1, text: "line \(index)", kind: .removed), new: nil)
        }
        document.setContent(rows: rows, width: 1_000)
        XCTAssertEqual(document.frame.height, 210_000)
        XCTAssertEqual(document.renderedRowRange.lowerBound, 0)
        XCTAssertLessThan(document.renderedRowRange.count, 50)
        XCTAssertTrue(document.renderedRowRange.contains(19))

        scroll.contentView.scroll(to: NSPoint(x: 100, y: 209_580))
        document.updateVisibleRows()
        XCTAssertEqual(document.renderedRowRange.upperBound, 10_000)
        XCTAssertLessThan(document.renderedRowRange.count, 50)
        XCTAssertTrue(document.renderedRowRange.contains(9_999))

        scroll.contentView.scroll(to: .zero)
        document.setContent(rows: Array(rows.prefix(2)), width: 600)
        XCTAssertEqual(document.renderedRowRange, 0..<2)
        document.setContent(rows: [], width: 600)
        XCTAssertEqual(document.renderedRowRange, 0..<0)
    }

    @MainActor func testVerticalScrollStaysAlignedFromEitherSide() {
        let old = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 420))
        let new = NSScrollView(frame: old.frame)
        old.documentView = VirtualizedDiffDocumentView(lines: \.old)
        new.documentView = VirtualizedDiffDocumentView(lines: \.new)
        old.documentView?.frame.size = NSSize(width: 1_000, height: 21_000)
        new.documentView?.frame.size = NSSize(width: 1_000, height: 21_000)
        let sync = HorizontalScrollSync()
        sync.register(old, for: .old)
        sync.register(new, for: .new)
        old.contentView.scroll(to: NSPoint(x: 100, y: 8_400))
        sync.didScroll(old, side: .old)
        XCTAssertEqual(new.contentView.bounds.origin.y, 8_400, accuracy: 0.5)
        XCTAssertEqual(new.contentView.bounds.origin.x, 100, accuracy: 0.5)
        new.contentView.scroll(to: NSPoint(x: 200, y: 16_800))
        sync.didScroll(new, side: .new)
        XCTAssertEqual(old.contentView.bounds.origin.y, 16_800, accuracy: 0.5)
    }
}
