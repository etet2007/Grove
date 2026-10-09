import AppKit
import XCTest
@testable import MyGit

final class SidebarResizeTests: XCTestCase {
    @MainActor func testFullScreenGrowthPreservesSidebarAndManualWidth() {
        let split = NavigationSplitView(frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
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
