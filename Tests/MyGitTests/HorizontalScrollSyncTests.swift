import AppKit
import SwiftUI
import XCTest
@testable import MyGit

final class HorizontalScrollSyncTests: XCTestCase {
    @MainActor func testSplitDiffKeepsBothScrollDirectionsAvailableInVisiblePanes() {
        let rows = (0..<100).map { index in
            DiffRow(id: index,
                    old: DiffLine(number: index + 1, text: String(repeating: "a", count: 200), kind: .removed),
                    new: DiffLine(number: index + 1, text: String(repeating: "b", count: 200), kind: .added))
        }
        let host = NSHostingView(rootView: SplitDiffView(
            diff: SplitDiff(rows: rows, hasChanges: true),
            oldTitle: "暂存区", newTitle: "工作区", resetID: "test"
        ))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        let scrollViews = descendants(of: host).compactMap { $0 as? NSScrollView }
        let panes = scrollViews.filter { $0.hasHorizontalScroller }
        XCTAssertEqual(panes.count, 2)
        XCTAssertTrue(panes.allSatisfy { !$0.autohidesScrollers })
        XCTAssertTrue(panes.contains { $0.hasVerticalScroller })
        XCTAssertTrue(panes.allSatisfy { $0.frame.height < 400 })
        let frames = panes.map { $0.convert($0.bounds, to: host) }.sorted { $0.minX < $1.minX }
        XCTAssertEqual(frames[0].maxX, 399.5, accuracy: 2)
        XCTAssertEqual(frames[1].minX, 400.5, accuracy: 2)
    }

    @MainActor private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor func testEitherPaneMovesTheOtherByTheSameOffset() {
        let old = makeScrollView()
        let new = makeScrollView()
        let sync = HorizontalScrollSync()
        sync.register(old, for: .old)
        sync.register(new, for: .new)

        old.contentView.scroll(to: NSPoint(x: 180, y: 0))
        sync.didScroll(old, side: .old)
        XCTAssertEqual(new.contentView.bounds.origin.x, 180, accuracy: 0.5)

        new.contentView.scroll(to: NSPoint(x: 320, y: 0))
        sync.didScroll(new, side: .new)
        XCTAssertEqual(old.contentView.bounds.origin.x, 320, accuracy: 0.5)

        old.contentView.scroll(to: NSPoint(x: 320, y: 250))
        sync.didScroll(old, side: .old)
        XCTAssertEqual(new.contentView.bounds.origin.y, 250, accuracy: 0.5)

        new.contentView.scroll(to: NSPoint(x: 320, y: 400))
        sync.didScroll(new, side: .new)
        XCTAssertEqual(old.contentView.bounds.origin.y, 400, accuracy: 0.5)
    }

    @MainActor private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 1_000))
        return scrollView
    }
}
