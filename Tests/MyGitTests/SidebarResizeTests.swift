import AppKit
import SwiftUI
import XCTest
@testable import MyGit

final class SidebarResizeTests: XCTestCase {
    @MainActor func testHostedSplitFillsWindowAndPreservesDraggedSidebarWidth() throws {
        let host = NSHostingView(rootView: SidebarSplitView(initialWidth: 280) {
            Text("Repositories").frame(maxWidth: .infinity, maxHeight: .infinity)
        } content: {
            Text("Diff").frame(maxWidth: .infinity, maxHeight: .infinity)
        })
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        host.layoutSubtreeIfNeeded()
        let split = try XCTUnwrap(descendants(host).compactMap { $0 as? MyGit.NavigationSplitView }.first)
        split.setPosition(340, ofDividerAt: 0)
        for size in [NSSize(width: 1800, height: 950), NSSize(width: 1100, height: 650), NSSize(width: 1500, height: 800)] {
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(split.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(split.frame.height, size.height, accuracy: 1)
            XCTAssertEqual(split.arrangedSubviews[0].frame.width, 340, accuracy: 2)
            XCTAssertEqual(split.arrangedSubviews[1].frame.maxX, size.width, accuracy: 1)
            XCTAssertEqual(split.arrangedSubviews[1].frame.height, size.height, accuracy: 1)
        }
    }

    @MainActor func testFullScreenGrowthPreservesSidebarAndManualWidth() {
        let split = MyGit.NavigationSplitView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 700)))
        split.addArrangedSubview(NSView(frame: NSRect(x: 281, y: 0, width: 919, height: 700)))
        split.preferredSidebarWidth = 280
        split.adjustSubviews()
        let width = split.arrangedSubviews[0].frame.width
        split.setFrameSize(NSSize(width: 2400, height: 1000))
        split.adjustSubviews()
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, width, accuracy: 2)
        XCTAssertGreaterThan(split.arrangedSubviews[1].frame.width, 2000)
        split.setPosition(430, ofDividerAt: 0)
        split.setFrameSize(NSSize(width: 1600, height: 800))
        split.adjustSubviews()
        XCTAssertEqual(split.arrangedSubviews[0].frame.width, 430, accuracy: 2)
    }
}
