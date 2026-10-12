import AppKit
import SwiftUI
import XCTest
@testable import MyGit

final class BranchPickerTests: XCTestCase {
    @MainActor func testLongPickerHasBoundedScrollableViewport() throws {
        let host = NSHostingView(rootView: PickerScrollView {
            VStack {
                ForEach(0..<100) { index in
                    Text("branch-\(index)").frame(height: 28)
                }
            }
        })
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 360)
        host.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        XCTAssertLessThanOrEqual(scroll.frame.height, 360, "The scroll view itself must fit inside the picker")
        XCTAssertGreaterThan(scroll.contentView.bounds.height, 0)
        let start = scroll.contentView.bounds.origin.y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: start + 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, start, "Scrolling must move the list inside the bounded viewport")
    }

    func testToolStashFilteringKeepsCurrentBranchAndSupportsSearchAndOptIn() {
        let branches = [
            LocalBranch(name: "ugit-stash/041a0fe-1", checkoutPath: nil),
            LocalBranch(name: "feature/Search", checkoutPath: "/other-checkout"),
            LocalBranch(name: "ugit-stash/041a0fe-3", checkoutPath: nil),
            LocalBranch(name: "main", checkoutPath: "/current-checkout"),
            LocalBranch(name: "ugit-stash/my-feature", checkoutPath: nil)
        ]
        let normal = BranchPickerOptions.visibleBranches(branches, current: "main", query: "", showToolStashes: false)
        XCTAssertEqual(normal.map(\.name), ["main", "feature/Search", "ugit-stash/my-feature"])
        XCTAssertEqual(normal.first { $0.name == "feature/Search" }?.checkoutPath, "/other-checkout")
        XCTAssertEqual(BranchPickerOptions.visibleBranches(branches, current: "main", query: "  SEARCH ", showToolStashes: false).map(\.name), ["feature/Search"])
        XCTAssertEqual(BranchPickerOptions.visibleBranches(branches, current: "main", query: "041a0fe", showToolStashes: true).count, 2)
        let currentStash = BranchPickerOptions.visibleBranches(branches, current: "ugit-stash/041a0fe-1", query: "", showToolStashes: false)
        XCTAssertEqual(currentStash.first?.name, "ugit-stash/041a0fe-1")
        XCTAssertFalse(currentStash.contains { $0.name == "ugit-stash/041a0fe-3" })
        XCTAssertFalse(BranchPickerOptions.isToolStash("ugit-stash/my-feature"))
        XCTAssertFalse(BranchPickerOptions.isToolStash("feature/ugit-stash/041a0fe-1"))
        XCTAssertFalse(BranchPickerOptions.isToolStash("ugit-stash/041a0fe-2"))
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
