import AppKit
import SwiftUI
import XCTest
@testable import MyGit

final class RetainedPaneTests: XCTestCase {
    @MainActor func testHiddenRepositoryDetailsKeepTheirViewportAndScrollPosition() async throws {
        let fixture = try await Fixture(repositoryCount: 3)
        defer { fixture.close() }
        let model = fixture.model
        let changesDocuments = documents(in: fixture.host)
        XCTAssertEqual(changesDocuments.count, 2, "Unvisited repository details should not mount or take part in layout")

        model.selectCommitRepository(fixture.repositories[0].id)
        model.activeTab = 1
        try await settle(fixture.host)
        let historyDocuments = documents(in: fixture.host).filter { candidate in
            !changesDocuments.contains { $0 === candidate }
        }
        XCTAssertEqual(historyDocuments.count, 2)
        let document = try XCTUnwrap(historyDocuments.first)
        let scroll = try XCTUnwrap(document.enclosingScrollView)
        scroll.contentView.scroll(to: NSPoint(x: 10, y: 1200))
        scroll.reflectScrolledClipView(scroll.contentView)
        document.updateVisibleRows()
        let origin = scroll.contentView.bounds.origin

        model.activeTab = 0
        try await settle(fixture.host)
        let hiddenSize = scroll.frame.size
        fixture.window.setContentSize(NSSize(width: 1700, height: 950))
        try await settle(fixture.host)
        XCTAssertEqual(scroll.frame.size, hiddenSize, "A hidden detail must not relayout as the window grows")
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)

        model.activeTab = 1
        try await settle(fixture.host)
        XCTAssertEqual(documents(in: fixture.host).count, 2, "Only the selected detail belongs to the live layout tree")
        XCTAssertTrue(documents(in: fixture.host).contains { $0 === document }, "Returning must reuse the native scroll view")
        XCTAssertEqual(scroll.contentView.bounds.origin, origin, "Returning must restore both scroll axes")
        XCTAssertNotEqual(scroll.frame.size, hiddenSize, "The selected detail must catch up to the current window size")
        XCTAssertEqual(model.currentCommitScope.detail.selectedFile?.path, "file.swift")
    }

    @MainActor func testListFocusRequestLeavesTheSearchEditor() async throws {
        let fixture = try await Fixture(repositoryCount: 1)
        defer { fixture.close() }
        fixture.window.makeKeyAndOrderFront(nil)
        try await settle(fixture.host)
        func editableFields(in view: NSView) -> [NSTextField] {
            view.subviews.flatMap { child in
                if let field = child as? NSTextField, field.isEditable { return [field] }
                return editableFields(in: child)
            }
        }
        for tab in [0, 1] {
            fixture.model.activeTab = tab
            try await settle(fixture.host)
            let search = try XCTUnwrap(editableFields(in: fixture.host).first)
            XCTAssertTrue(fixture.window.makeFirstResponder(search))
            let editor = try XCTUnwrap(fixture.window.firstResponder)
            fixture.model.listFocusRequest = UUID()
            try await settle(fixture.host)
            XCTAssertNotNil(fixture.window.firstResponder)
            XCTAssertFalse(fixture.window.firstResponder === editor, "A focus request must leave the search editor and reach the current list (tab \(tab))")
        }
    }

    @MainActor func testResizeBenchmarkWithSixHiddenRepositoryDetails() async throws {
        guard ProcessInfo.processInfo.environment["MYGIT_RESIZE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MYGIT_RESIZE_BENCHMARK=1 to measure hidden repository layout")
        }
        let fixture = try await Fixture(repositoryCount: 6)
        defer { fixture.close() }
        // Visit each repository so this measures retained pages, not only lazy mounting.
        fixture.model.activeTab = 1
        for repository in fixture.repositories {
            fixture.model.selectCommitRepository(repository.id)
            try await settle(fixture.host)
        }
        fixture.model.activeTab = 0
        try await settle(fixture.host)
        var samples: [Double] = []
        let iterations = max(60, Int(ProcessInfo.processInfo.environment["MYGIT_RETAINED_ITERATIONS"] ?? "60") ?? 60)
        for index in 0..<iterations {
            let start = CACurrentMediaTime()
            fixture.window.setContentSize(NSSize(width: 1500 + (index % 60) * 3, height: 800 + (index % 60) * 2))
            fixture.host.layoutSubtreeIfNeeded()
            fixture.window.displayIfNeeded()
            if index >= 10 { samples.append((CACurrentMediaTime() - start) * 1000) }
        }
        samples.sort()
        print(String(format: "RETAINED RESIZE six repositories: median %.2f ms, p95 %.2f ms", samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)]))
        XCTAssertLessThan(samples[samples.count / 2], 16.7)
    }

    @MainActor private func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(30))
        host.layoutSubtreeIfNeeded()
        host.window?.displayIfNeeded()
    }

    @MainActor private func documents(in view: NSView) -> [VirtualizedDiffDocumentView] {
        view.subviews.flatMap { child in
            (child as? VirtualizedDiffDocumentView).map { [$0] } ?? documents(in: child)
        }
    }

    @MainActor private final class Fixture {
        let directory: URL
        let model: AppModel
        let repositories: [Repository]
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init(repositoryCount: Int) async throws {
            let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitRetained-\(UUID())")
            directory = fixtureDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var project = Project(name: "Retained layouts")
            // No worktree group is configured: fixture data is synthetic and no repository reads run.
            project.repositories = (0..<repositoryCount).map {
                Repository(name: "Repo \($0)", path: fixtureDirectory.appendingPathComponent("repo\($0)").path, groupID: UUID())
            }
            repositories = project.repositories
            let config = directory.appendingPathComponent("config.json")
            try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id)).write(to: config)
            model = AppModel(configURL: config)
            model.automaticRefreshEnabled = false
            let deadline = Date().addingTimeInterval(5)
            while model.isRefreshing, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            let text = "--- a/file.swift\n+++ b/file.swift\n@@ -1,1000 +1,1000 @@\n" +
                (0..<1000).map { "-let oldValue\($0) = calculate(input: \($0))\n+let newValue\($0) = calculate(input: \($0 + 1))" }.joined(separator: "\n")
            let diff = SplitDiff.parse(text)
            func populate(_ state: DetailState, repositoryID: UUID) {
                state.selectedFile = ChangedFile(repositoryID: repositoryID, path: "file.swift", indexStatus: " ", worktreeStatus: "M", isUntracked: false)
                state.detail = text
                state.splitDiff = diff
            }
            populate(model.detailStates[0], repositoryID: UUID())
            for repository in repositories {
                model.selectCommitRepository(repository.id)
                populate(model.currentCommitScope.detail, repositoryID: repository.id)
            }
            model.activeTab = 0
            host = NSHostingView(rootView: AnyView(ContentView().environmentObject(model)))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            host.layoutSubtreeIfNeeded()
        }

        func close() {
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
