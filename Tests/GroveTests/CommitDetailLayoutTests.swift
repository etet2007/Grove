import AppKit
import SwiftUI
import XCTest
@testable import Grove

final class CommitDetailLayoutTests: XCTestCase {
    @MainActor
    func testFileListHasDraggableDividerAndLeavesRoomForDiff() throws {
        let text = (0..<11).map { index in
            """
            diff --git a/file\(index).txt b/file\(index).txt
            --- a/file\(index).txt
            +++ b/file\(index).txt
            @@ -1 +1 @@
            -before
            +after
            """
        }.joined(separator: "\n")
        let host = NSHostingView(rootView: CommitDetailView(patch: CommitPatch.parse(text),
                                                           layout: .patch, checkoutPath: nil))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layoutSubtreeIfNeeded()
        let split = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSplitView }.first { !$0.isVertical },
                                  "The file list and diff must share a draggable horizontal divider")
        XCTAssertEqual(split.arrangedSubviews.count, 2)
        let list = split.arrangedSubviews[0]
        let detail = split.arrangedSubviews[1]
        let initialHeight = list.frame.height
        split.setPosition(100, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        XCTAssertEqual(list.frame.height, 100, accuracy: 2)
        XCTAssertNotEqual(list.frame.height, initialHeight)
        split.setPosition(300, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
        XCTAssertEqual(list.frame.height, 300, accuracy: 2)
        XCTAssertGreaterThan(detail.frame.height, 160)
        XCTAssertFalse(descendants(list).compactMap { $0 as? NSScrollView }.isEmpty,
                       "The file list must stay scrollable when its height is reduced")
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
