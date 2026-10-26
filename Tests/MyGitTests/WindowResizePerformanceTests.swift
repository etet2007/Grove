import AppKit
import SwiftUI
import XCTest
@testable import MyGit

final class WindowResizePerformanceTests: XCTestCase {
    // Opt in on an idle machine; wall-clock thresholds should not gate CI under load.
    // MYGIT_RESIZE_BENCHMARK=1 swift test --filter WindowResizePerformanceTests
    @MainActor func testDiffWindowResizeBudget() async throws {
        guard ProcessInfo.processInfo.environment["MYGIT_RESIZE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MYGIT_RESIZE_BENCHMARK=1 to measure actual window layout and drawing")
        }
        let text = "--- a/file.swift\n+++ b/file.swift\n@@ -1,1000 +1,1000 @@\n" +
            (0..<1000).map { "-let oldValue\($0) = calculate(input: \($0))\n+let newValue\($0) = calculate(input: \($0 + 1))" }.joined(separator: "\n")
        let diff = SplitDiff.parse(text)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitResize-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Resize fixture")
        let config = directory.appendingPathComponent("config.json")
        try JSONEncoder().encode(Configuration(projects: [project], selectedProjectID: project.id)).write(to: config)
        let model = AppModel(configURL: config)
        model.automaticRefreshEnabled = false
        let deadline = Date().addingTimeInterval(5)
        while model.isRefreshing, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.isRefreshing)
        model.detailStates[0].selectedFile = ChangedFile(repositoryID: UUID(), path: "file.swift", indexStatus: " ", worktreeStatus: "M", isUntracked: false)
        model.detailStates[0].detail = text
        model.detailStates[0].splitDiff = diff
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(model))
        window.orderFront(nil)
        var samples: [Double] = []
        let iterations = max(50, Int(ProcessInfo.processInfo.environment["MYGIT_RESIZE_ITERATIONS"] ?? "50") ?? 50)
        for index in 0..<iterations {
            let start = CACurrentMediaTime()
            window.setContentSize(NSSize(width: 1500 + (index % 50) * 4, height: 800 + (index % 50) * 2))
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if index >= 10 { samples.append((CACurrentMediaTime() - start) * 1000) }
        }
        samples.sort()
        print(String(format: "RESIZE median %.2f ms, p95 %.2f ms", samples[samples.count / 2], samples[Int(Double(samples.count) * 0.95)]))
        XCTAssertLessThan(samples[samples.count / 2], 16.7, "Resizing exceeds a 60 Hz frame budget")
    }
}
