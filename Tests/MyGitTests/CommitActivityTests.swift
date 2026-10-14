import XCTest
@testable import MyGit

final class CommitActivityTests: XCTestCase {
    func testProcessStreamsStdoutAndStderrBeforeExit() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitStream-\(UUID())")
        defer { try? FileManager.default.removeItem(at: marker) }
        var stdout = Data(), stderr = Data(), receivedBeforeExit = false
        let result = try CommitProcess.run("/bin/sh", ["-c", "printf 'ready\\n'; printf 'diagnostic\\n' >&2; sleep 0.3; touch \"$1\"; printf 'done\\n'", "test", marker.path],
                                           in: FileManager.default.temporaryDirectory.path, onOutput: { stream, chunk in
            if stream == .stdout {
                stdout.append(chunk)
                if String(decoding: stdout, as: UTF8.self).contains("ready"), !FileManager.default.fileExists(atPath: marker.path) { receivedBeforeExit = true }
            } else { stderr.append(chunk) }
        })
        XCTAssertTrue(receivedBeforeExit, "Progress must arrive while the process is still running")
        XCTAssertEqual(stdout, result.data)
        XCTAssertEqual(String(decoding: stderr, as: UTF8.self), result.diagnostic)
        XCTAssertEqual(result.status, 0)
    }

    func testDecoderFramesSplitUTF8AndDoesNotExposePrivateThinking() throws {
        var events: [CommitActivity] = []
        let decoder = CommitAgentActivityDecoder(kind: .omp) { events.append($0) }
        let thinking = try JSONSerialization.data(withJSONObject: ["type": "message_update", "assistantMessageEvent": ["type": "thinking_delta", "delta": "private scratchpad"]])
        let text = try JSONSerialization.data(withJSONObject: ["type": "message_update", "assistantMessageEvent": ["type": "text_delta", "delta": "正在整理提交文件"]])
        for byte in thinking + Data([10]) + text + Data([10]) { decoder.feed(.stdout, Data([byte])) }
        decoder.finish()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.detail, "正在整理提交文件")
    }

    func testCodexPublicSummaryAndCommandOutputAreVisible() throws {
        var events: [CommitActivity] = []
        let decoder = CommitAgentActivityDecoder(kind: .codex) { events.append($0) }
        for object: [String: Any] in [
            ["type": "turn.started"],
            ["type": "item.completed", "item": ["type": "reasoning", "text": "Separate documentation from the fix"]],
            ["type": "item.completed", "item": ["type": "command_execution", "command": "git diff", "aggregated_output": "sample output"]]
        ] {
            decoder.feed(.stdout, try JSONSerialization.data(withJSONObject: object) + Data([10]))
        }
        decoder.finish()
        XCTAssertTrue(events.contains { $0.detail == "Separate documentation from the fix" })
        XCTAssertTrue(events.contains { $0.detail == "git diff" })
        XCTAssertTrue(events.contains { $0.detail == "sample output" })
    }

    func testClaudeStreamingResultStillDecodesStructuredPlan() throws {
        let plan = CommitPlan(commits: [PlannedCommit(id: "one", message: "[DOCS]: Update usage", paths: ["README.md"], reason: "Documentation")], omitted: [])
        let encoded = try JSONEncoder().encode(plan)
        let envelope = try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false,
                                                                   "structured_output": JSONSerialization.jsonObject(with: encoded)])
        let data = Data("{\"type\":\"system\",\"subtype\":\"init\"}\n".utf8) + envelope + Data([10])
        XCTAssertEqual(try CommitAgentClient.decode(data, kind: .claude), plan)
        var events: [CommitActivity] = []
        let decoder = CommitAgentActivityDecoder(kind: .claude) { events.append($0) }
        decoder.feed(.stdout, data); decoder.finish()
        XCTAssertFalse(events.isEmpty)
    }

    func testFailureMessageNeverExposesPrivateThinkingEvents() {
        let data = Data("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_delta\",\"delta\":\"private scratchpad\"}}\n".utf8)
        let output = CommitProcess.Output(status: 1, data: data, diagnostic: "")
        XCTAssertFalse(CommitAgentClient.publicFailure(output).contains("private scratchpad"))
    }

    func testOmpSummaryBeforeFinalJsonDoesNotBreakPlanParsing() throws {
        let plan = CommitPlan(commits: [PlannedCommit(id: "one", message: "[DOCS]: Explain {first use}", paths: ["README.md"], reason: "Quote: \"read-only\"")], omitted: [])
        let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        let text = "I inspected the skill and repository.\n\n```json\n\(json)\n```"
        let event = try JSONSerialization.data(withJSONObject: ["type": "message_end", "message": ["role": "assistant", "content": [["type": "text", "text": text]]]])
        XCTAssertEqual(try CommitAgentClient.decode(event, kind: .omp), plan)
    }

    func testGitHookOutputAndCommitCompletionAreReportedInOrder() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MyGitHookActivity-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        _ = try GitClient.text(["config", "commit.gpgsign", "false"], in: root.path)
        try Data("sample\n".utf8).write(to: root.appendingPathComponent("new.txt"))
        let hook = root.appendingPathComponent(".git/hooks/pre-commit")
        try Data("#!/bin/sh\necho 'checking example' >&2\nsleep 0.2\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let plan = CommitPlan(commits: [PlannedCommit(id: "one", message: "[FEATURE]: Add sample", paths: ["new.txt"], reason: "test")], omitted: [])
        var events: [CommitActivity] = []
        let result = CommitExecutor.execute(plan, snapshot: snapshot, progress: { events.append($0) })
        XCTAssertNil(result.failure)
        let output = try XCTUnwrap(events.firstIndex { $0.detail.contains("checking example") })
        let done = try XCTUnwrap(events.firstIndex { $0.kind == .completed })
        XCTAssertLessThan(output, done)
        XCTAssertEqual(events[done].detail, result.hashes.first)
        XCTAssertTrue(events.contains { $0.detail.contains(AppLocalization.text("完成，耗时 %.2f 秒", 0).components(separatedBy: "0.00")[0]) })
    }

    func testTimeoutRemainsBoundedWithEventBasedWaiting() throws {
        let start = Date()
        XCTAssertThrowsError(try CommitProcess.run("/bin/sh", ["-c", "exec sleep 5"], in: FileManager.default.temporaryDirectory.path, timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testOutputRedactsCredentialsAndTerminalControlSequences() {
        XCTAssertEqual(CommitOutputText.clean("\u{1b}[31mwarning\u{1b}[0m"), "warning")
        XCTAssertEqual(CommitOutputText.clean("Bearer example-secret-token"), "Bearer <REDACTED>")
        XCTAssertEqual(CommitOutputText.clean("sk-example-secret-token"), "<REDACTED>")
    }

    @MainActor func testActivityLogBoundsOutputAndIgnoresPriorRunCallbacks() async throws {
        let log = CommitActivityLog()
        let old = log.begin("old")
        _ = log.begin("new")
        old(CommitActivity("stale", detail: "must not appear"))
        for _ in 0..<160 { log.append(CommitActivity("output", detail: String(repeating: "x", count: 2000), kind: .output)) }
        await Task.yield()
        XCTAssertLessThanOrEqual(log.events.count, 150)
        XCTAssertLessThanOrEqual(log.events.reduce(0) { $0 + $1.detail.count }, 60_000)
        XCTAssertFalse(log.events.contains { $0.title == "stale" })
        log.finish("done")
        XCTAssertFalse(log.running)
    }
}
