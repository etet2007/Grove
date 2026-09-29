import AppKit
import XCTest
@testable import MyGit

final class HorizontalScrollSyncTests: XCTestCase {
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
    }

    @MainActor private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 40))
        return scrollView
    }
}
