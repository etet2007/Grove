import AppKit
import SwiftUI
import XCTest
@testable import Grove

final class DiffPreviewWindowTests: XCTestCase {
    @MainActor func testClosingPreviewReleasesReferencesAndCanReopen() throws {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let presenter = DiffPreviewWindow<Text>.Coordinator()
        presenter.show(AnyView(Text("First file")), parent: parent, animated: false)
        let oldWindow = try XCTUnwrap(presenter.window)
        XCTAssertNotNil(presenter.host)
        XCTAssertFalse(oldWindow.styleMask.contains(.fullScreen))
        XCTAssertFalse(oldWindow.collectionBehavior.contains(.fullScreenPrimary))
        if let screen = parent.screen {
            XCTAssertEqual(oldWindow.frame, screen.visibleFrame)
        }
        presenter.close(animated: false)
        XCTAssertNil(presenter.window)
        XCTAssertNil(presenter.host)
        XCTAssertFalse(oldWindow.isVisible)
        presenter.show(AnyView(Text("Second file")), parent: parent, animated: false)
        XCTAssertNotNil(presenter.window)
        XCTAssertFalse(presenter.window === oldWindow)
        presenter.close(animated: false)
    }

    @MainActor func testClosingParentAlsoClosesPreview() {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let presenter = DiffPreviewWindow<Text>.Coordinator()
        presenter.show(AnyView(Text("File diff")), parent: parent, animated: false)
        parent.close()
        XCTAssertNil(presenter.window)
        XCTAssertNil(presenter.host)
    }

    @MainActor func testAnimatedPreviewFinishesAndCanCloseDuringExpansion() async throws {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let presenter = DiffPreviewWindow<Text>.Coordinator()
        presenter.sourceRect = NSRect(x: 100, y: 300, width: 280, height: 36)
        presenter.show(AnyView(Text("File diff")), parent: parent)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(try XCTUnwrap(presenter.host).isHidden)
        presenter.close()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(presenter.window)
        presenter.show(AnyView(Text("Another file")), parent: parent)
        presenter.close()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(presenter.window)
        XCTAssertNil(presenter.host)
    }

    @MainActor func testOriginUsesRowCoordinatesInItsWindow() throws {
        let parent = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let row = NSView(frame: NSRect(x: 20, y: 250, width: 300, height: 40))
        try XCTUnwrap(parent.contentView).addSubview(row)
        let origin = DiffPreviewOrigin()
        origin.register(row, for: "selected")
        XCTAssertEqual(origin.screenRect(for: "selected"), parent.convertToScreen(row.frame))
        origin.remove(row, for: "selected")
        XCTAssertNil(origin.screenRect(for: "selected"))
    }

}
