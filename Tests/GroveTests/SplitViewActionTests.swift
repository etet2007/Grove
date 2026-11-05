import AppKit
import SwiftUI
import XCTest
@testable import Grove

final class SplitViewActionTests: XCTestCase {
    @MainActor
    func testSidebarMenuActionLookupDoesNotRecurseThroughSplitDelegate() {
        let split = Grove.NavigationSplitView()
        assertMenuActionLookup(split)
    }

    @MainActor
    func testDiffMenuActionLookupDoesNotRecurseThroughSplitDelegate() throws {
        let host = NSHostingView(rootView: SplitDiffView(
            diff: SplitDiff(rows: [], hasChanges: false),
            oldTitle: "Index", newTitle: "Working tree", resetID: "menu-action"
        ))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        host.layoutSubtreeIfNeeded()
        let split = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSplitView }.first)
        assertMenuActionLookup(split)
    }

    @MainActor
    private func assertMenuActionLookup(_ split: NSSplitView) {
        let action = NSSelectorFromString("toggleSidebar:")
        // AppKit queries this selector while validating menus, including the
        // automatic startup menu scan shown in the crash report.
        XCTAssertFalse(split.responds(to: action))
        XCTAssertNotNil(split.delegate)
        XCTAssertFalse((split.delegate as AnyObject?) === split)
        XCTAssertTrue(split.delegate?.responds(to:
            #selector(NSSplitViewDelegate.splitView(_:constrainMinCoordinate:ofSubviewAt:))) == true)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
