import AppKit
import SwiftUI
import XCTest
@testable import Grove

final class DiffScrollPerformanceTests: XCTestCase {
    // Opt in on an idle desktop: GROVE_SCROLL_BENCHMARK=1 swift test --filter DiffScrollPerformanceTests
    @MainActor func testSynchronizedDiffScrollFrameBudget() throws {
        guard ProcessInfo.processInfo.environment["GROVE_SCROLL_BENCHMARK"] == "1" else {
            throw XCTSkip("Set GROVE_SCROLL_BENCHMARK=1 to measure diff scrolling")
        }
        let patch = "--- a/file.kt\n+++ b/file.kt\n@@ -1,1000 +1,1000 @@\n" +
            (0..<1000).map { "-private val oldValue\($0) = Codec.deriveKeys(ByteArray(32) { it.toByte() })\n+private val newValue\($0) = Codec.deriveKeys(ByteArray(32) { it.toByte() })" }.joined(separator: "\n")
        let diff = SplitDiff.parse(patch)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: SplitDiffView(diff: diff, oldTitle: "Before", newTitle: "After", resetID: "benchmark"))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        func documents(_ view: NSView) -> [VirtualizedDiffDocumentView] {
            if let document = view as? VirtualizedDiffDocumentView { return [document] }
            return view.subviews.flatMap { documents($0) }
        }
        let panes = documents(host)
        XCTAssertEqual(panes.count, 2)
        let source = try XCTUnwrap(panes.first?.enclosingScrollView)
        var samples: [Double] = []
        let wheel = ProcessInfo.processInfo.environment["GROVE_SCROLL_WHEEL"] == "1"
        let event = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                           wheelCount: 1, wheel1: -6, wheel2: 0, wheel3: 0)!)!

        for index in 0..<100 {
            let start = CACurrentMediaTime()
            if wheel {
                source.scrollWheel(with: event)
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            } else {
                source.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(index * 42)))
                source.reflectScrolledClipView(source.contentView)
            }
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if index >= 10 { samples.append((CACurrentMediaTime() - start) * 1000) }
        }
        if wheel {
            XCTAssertEqual(source.contentView.bounds.origin.y, 600 * source.verticalLineScroll, accuracy: 1,
                           "Rapid wheel input must not leave a delayed scrolling destination")
        }
        print("SCROLL MODE \(wheel ? "wheel" : "position"), final y \(source.contentView.bounds.origin.y)")
        samples.sort()
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        print(String(format: "DIFF SCROLL median %.2f ms, p95 %.2f ms", samples[samples.count / 2], p95))
        XCTAssertLessThan(p95, 16.7, "Diff scrolling exceeds a 60 Hz frame budget")
        XCTAssertEqual(panes[0].enclosingScrollView?.contentView.bounds.origin.y,
                       panes[1].enclosingScrollView?.contentView.bounds.origin.y)
    }
}
