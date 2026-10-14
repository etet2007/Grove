import XCTest
@testable import MyGit

final class CommitExecutionTests: XCTestCase {
    func testProcessRunnerAvoidsAccumulatedPollingDelay() throws {
        let directory = FileManager.default.temporaryDirectory.path
        let start = Date()
        for _ in 0..<8 { _ = try CommitProcess.run("/usr/bin/true", [], in: directory) }
        let elapsed = Date().timeIntervalSince(start)
        print("COMMIT timing: eight no-op subprocesses \(elapsed)s")
        XCTAssertLessThan(elapsed, 0.15, "Per-command polling delay accumulates across commit validation commands")
    }

    func testCommitTimingBenchmark() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edit\n", "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let start = Date()
        let result = CommitExecutor.execute(plan([["a.txt"]]), snapshot: snapshot)
        print("COMMIT timing: one-file commit \(Date().timeIntervalSince(start))s")
        XCTAssertNil(result.failure)
    }

    func testLargeDiffIsAvailableForReviewWithoutAgentInputLimit() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write(String(repeating: "changed source line\n", count: 25_000), "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        XCTAssertGreaterThan(snapshot.files[0].patch.utf8.count, 400_000)
        try snapshot.validate()
        let prompt = try CommitAgentClient.makePrompt(snapshot: snapshot, skill: root.appendingPathComponent("SKILL.md"), intent: "understand changes")
        XCTAssertTrue(prompt.contains("a.txt"))
        XCTAssertFalse(prompt.contains("changed source line"))
        XCTAssertLessThan(prompt.utf8.count, 10_000)
    }

    func testLargeFileFingerprintAndDiffAreNotLimitedToEightMegabytes() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write(String(repeating: "large file content\n", count: 500_000), "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        XCTAssertGreaterThan(snapshot.files[0].patch.utf8.count, 8_000_000)
        try snapshot.validate()
    }

    func testAgentLaunchUsesRealCheckoutAndEnablesReadingTools() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edit\n", "a.txt", root)
        try write("Read the changes\n", "SKILL.md", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitLaunch-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        for kind in CommitAgentKind.allCases {
            let prefs = CommitPreferences(kind: kind, executable: "/custom/agent", skillPath: root.appendingPathComponent("SKILL.md").path)
            let launch = try CommitAgentLaunch.prepare(snapshot: snapshot, preferences: prefs,
                                                       skill: root.appendingPathComponent("SKILL.md"), temporary: temp, schema: CommitAgentClient.schema)
            XCTAssertEqual(launch.directory, root.path)
            XCTAssertEqual(launch.executable, kind == .codex ? "/custom/agent" : "/usr/bin/sandbox-exec")
            XCTAssertFalse(launch.arguments.contains("--no-tools"))
            if kind == .codex { XCTAssertTrue(launch.arguments.contains("read-only")) }
            else { XCTAssertTrue(launch.arguments.contains(where: { $0 == "--tools" || $0.hasPrefix("--tools=") })) }
        }
    }

    func testAgentSandboxAllowsReadsAndDeniesFileAndGitWrites() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edit\n", "a.txt", root)
        let before = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let profile = CommitAgentLaunch.readOnlyProfile(protectedPaths: [root.path])
        let read = try CommitProcess.run("/usr/bin/sandbox-exec", ["-p", profile, "/usr/bin/git", "diff", "--", "a.txt"],
                                         in: root.path, environment: ["GIT_OPTIONAL_LOCKS": "0"])
        XCTAssertEqual(read.status, 0, read.diagnostic); XCTAssertTrue(String(decoding: read.data, as: UTF8.self).contains("edit"))
        for args in [["/usr/bin/touch", root.appendingPathComponent("must-not-exist").path],
                     ["/usr/bin/git", "add", "a.txt"], ["/usr/bin/git", "commit", "--allow-empty", "-m", "unsafe"]] {
            let output = try CommitProcess.run("/usr/bin/sandbox-exec", ["-p", profile] + args, in: root.path)
            XCTAssertNotEqual(output.status, 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("must-not-exist").path))
        try before.validate()
    }

    func testAgentSandboxProtectsSharedGitDataOfLinkedWorktree() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.deletingLastPathComponent().appendingPathComponent("MyGitAgentLinked-\(UUID())")
        defer { try? FileManager.default.removeItem(at: checkout) }
        _ = try GitClient.text(["worktree", "add", "-b", "feature-read", checkout.path], in: root.path)
        let common = try CommitProcess.gitText(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: checkout.path)
        let profile = CommitAgentLaunch.readOnlyProfile(protectedPaths: [checkout.path, common])
        let output = try CommitProcess.run("/usr/bin/sandbox-exec", ["-p", profile, "/usr/bin/git", "config", "--local", "user.name", "unexpected"], in: checkout.path)
        XCTAssertNotEqual(output.status, 0)
        XCTAssertEqual(try GitClient.text(["config", "user.name"], in: root.path).trimmingCharacters(in: .whitespacesAndNewlines), "Test")
    }

    private func fixture(initial: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MyGitCommitTest-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        _ = try GitClient.text(["config", "commit.gpgsign", "false"], in: root.path)
        if initial {
            for name in ["a.txt", "b.txt", "keep.txt"] { try write("initial\n", name, root) }
            _ = try GitClient.text(["add", "."], in: root.path)
            _ = try GitClient.text(["commit", "-m", "initial"], in: root.path)
        }
        return root
    }

    private func write(_ value: String, _ name: String, _ root: URL) throws {
        try Data(value.utf8).write(to: root.appendingPathComponent(name))
    }

    private func plan(_ groups: [[String]], omitted: [String] = []) -> CommitPlan {
        CommitPlan(commits: groups.enumerated().map { index, paths in
            PlannedCommit(id: String(index), message: "[BUGFIX]: Change \(index)", paths: paths, reason: "test")
        }, omitted: omitted)
    }

    func testStagedSplitPreservesUnstagedContentAndUnselectedIndex() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("staged a\n", "a.txt", root); try write("staged b\n", "b.txt", root); try write("keep staged\n", "keep.txt", root)
        _ = try GitClient.text(["add", "."], in: root.path)
        try write("unstaged a\n", "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .staged)
        let result = CommitExecutor.execute(plan([["a.txt"], ["b.txt"]], omitted: ["keep.txt"]), snapshot: snapshot)
        XCTAssertNil(result.failure); XCTAssertEqual(result.hashes.count, 2)
        XCTAssertEqual(try GitClient.text(["show", "HEAD~1:a.txt"], in: root.path), "staged a\n")
        XCTAssertEqual(try GitClient.text(["show", ":keep.txt"], in: root.path), "keep staged\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("a.txt")), "unstaged a\n")
        XCTAssertEqual(try GitClient.text(["diff", "--cached", "--name-only"], in: root.path), "keep.txt\n")
    }

    func testAllScopeIncludesNewFilesAndDeletionWithLiteralPaths() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edited\n", "a.txt", root)
        try write("new\n", ":(glob)* space.txt", root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.txt"))
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["a.txt", "b.txt"], [":(glob)* space.txt"]]), snapshot: snapshot)
        XCTAssertNil(result.failure); XCTAssertEqual(result.hashes.count, 2)
        XCTAssertEqual(try GitClient.text(["status", "--porcelain"], in: root.path), "")
    }

    func testUnbornBranchCreatesFirstCommit() throws {
        let root = try fixture(initial: false); defer { try? FileManager.default.removeItem(at: root) }
        try write("hello\n", "new.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["new.txt"]]), snapshot: snapshot)
        XCTAssertNil(result.failure); XCTAssertEqual(result.hashes.count, 1)
        XCTAssertEqual(try GitClient.text(["status", "--porcelain"], in: root.path), "")
    }

    func testChangesDuringReviewRejectWithoutWriting() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("first\n", "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        try write("second\n", "a.txt", root)
        let result = CommitExecutor.execute(plan([["a.txt"]]), snapshot: snapshot)
        XCTAssertNotNil(result.failure); XCTAssertTrue(result.hashes.isEmpty)
        XCTAssertEqual(try CommitSnapshot.currentHead(root.path), snapshot.head)
        XCTAssertEqual(try CommitSnapshot.readIndex(snapshot.indexPath), snapshot.indexData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.indexPath + ".lock"))
        let next = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        _ = try GitClient.text(["add", "a.txt"], in: root.path)
        XCTAssertThrowsError(try next.validate())
    }

    func testHookFailureKeepsEarlierCommitAndRemainingEdits() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("new a\n", "a.txt", root); try write("new b\n", "b.txt", root)
        let hook = root.appendingPathComponent(".git/hooks/pre-commit")
        try write("#!/bin/sh\nif git diff --cached --name-only | /usr/bin/grep -q '^b.txt$'; then echo blocked >&2; exit 1; fi\n", ".git/hooks/pre-commit", root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["a.txt"], ["b.txt"]]), snapshot: snapshot)
        XCTAssertEqual(result.hashes.count, 1); XCTAssertNotNil(result.failure)
        XCTAssertEqual(try GitClient.text(["show", "HEAD:a.txt"], in: root.path), "new a\n")
        XCTAssertEqual(try GitClient.text(["show", "HEAD:b.txt"], in: root.path), "initial\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.txt")), "new b\n")
        XCTAssertEqual(try GitClient.text(["diff", "--cached", "--name-only"], in: root.path), "")
    }

    func testExistingLockAndInvalidPlansAreNeverOverwritten() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("new\n", "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let lock = URL(fileURLWithPath: snapshot.indexPath + ".lock")
        try Data("other process".utf8).write(to: lock)
        let result = CommitExecutor.execute(plan([["a.txt"]]), snapshot: snapshot)
        XCTAssertNotNil(result.failure); XCTAssertTrue(result.hashes.isEmpty)
        XCTAssertEqual(try String(contentsOf: lock), "other process")
        XCTAssertThrowsError(try plan([["a.txt"], ["a.txt"]]).validate(available: ["a.txt"]))
        XCTAssertThrowsError(try plan([["else.txt"]]).validate(available: ["a.txt"]))
        XCTAssertThrowsError(try plan([["a.txt"]]).validate(available: ["a.txt", "b.txt"]))
    }

    func testLinkedWorktreeUsesItsOwnIndexAndBranch() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let worktree = root.deletingLastPathComponent().appendingPathComponent("MyGitLinked-\(UUID())")
        defer { try? FileManager.default.removeItem(at: worktree) }
        _ = try GitClient.text(["worktree", "add", "-b", "feature", worktree.path], in: root.path)
        let mainHead = try CommitSnapshot.currentHead(root.path)
        try write("linked edit\n", "a.txt", worktree)
        let snapshot = try CommitSnapshot.capture(checkout: worktree.path, scope: .all)
        let result = CommitExecutor.execute(plan([["a.txt"]]), snapshot: snapshot)
        XCTAssertNil(result.failure); XCTAssertEqual(result.hashes.count, 1)
        XCTAssertEqual(try CommitSnapshot.currentHead(root.path), mainHead)
        XCTAssertEqual(try GitClient.text(["status", "--porcelain"], in: root.path), "")
    }

    func testSkillPathAndAgentResultFormats() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("Use [rules](convention.md).\n", "SKILL.md", root)
        try write("TYPE must be uppercase.\n", "convention.md", root)
        let skill = try CommitSkill.fileURL(path: root.appendingPathComponent("SKILL.md").path)
        XCTAssertEqual(skill.path, root.appendingPathComponent("SKILL.md").path)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: root.appendingPathComponent("convention.md").path))
        let value = plan([["a.txt"]])
        let json = try JSONEncoder().encode(value)
        XCTAssertEqual(try CommitAgentClient.decode(json, kind: .codex), value)
        let envelope = try JSONSerialization.data(withJSONObject: ["structured_output": JSONSerialization.jsonObject(with: json)])
        XCTAssertEqual(try CommitAgentClient.decode(envelope, kind: .claude), value)
        let event = try JSONSerialization.data(withJSONObject: ["type": "message_end", "message": ["role": "assistant", "content": [["type": "text", "text": String(decoding: json, as: UTF8.self)]]]])
        XCTAssertEqual(try CommitAgentClient.decode(event, kind: .omp), value)
    }

    func testLiveAgentGenerationWhenExplicitlyEnabled() throws {
        guard let name = ProcessInfo.processInfo.environment["MYGIT_TEST_AGENT"],
              let kind = CommitAgentKind(rawValue: name) else { throw XCTSkip("Live agent test is opt-in") }
        let agent = try XCTUnwrap(AgentDiscovery.detect().first { $0.kind == kind && $0.failure == nil })
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("document first use\n", "README.md", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let preferences = CommitPreferences(kind: kind, executable: agent.path,
                                            skillPath: NSHomeDirectory() + "/.codex/skills/commit-message/SKILL.md")
        var progressEvents: [CommitActivity] = []
        defer {
            for event in progressEvents where event.kind != .delta && (event.title == AppLocalization.text("Agent 正在读取仓库") || event.title == AppLocalization.text("Agent 输出") || event.title == AppLocalization.text("Agent 执行命令")) {
                print("AGENT activity: \(event.title) \(CommitOutputText.clean(String(event.detail.prefix(1500))))")
            }
            let streamed = progressEvents.filter { $0.kind == .delta }.map(\.detail).joined()
            if !streamed.isEmpty { print("AGENT streamed output: \(CommitOutputText.clean(String(streamed.prefix(3000))))") }
        }
        let value = try CommitAgentClient.generate(snapshot: snapshot, preferences: preferences, intent: "Add first-use documentation", progress: { progressEvents.append($0) })
        XCTAssertTrue(progressEvents.contains { $0.title == AppLocalization.text("Agent 已启动") })
        XCTAssertTrue(progressEvents.contains { $0.title == AppLocalization.text("Agent 输出") })
        XCTAssertTrue(progressEvents.contains { $0.title == AppLocalization.text("Agent 正在读取仓库") || $0.title == AppLocalization.text("Agent 执行命令") })
        try value.validate(available: ["README.md"])
        XCTAssertTrue(value.commits.first?.message.hasPrefix("[DOCS]") == true)
        try snapshot.validate()
    }

    func testAllScopeCommitsFinalFileWhileKeepingUnrelatedStagedAndUntrackedFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("staged\n", "a.txt", root); try write("keep staged\n", "keep.txt", root)
        _ = try GitClient.text(["add", "."], in: root.path)
        try write("final work file", "a.txt", root)
        try write("leave this\n", "new.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["a.txt"]], omitted: ["keep.txt", "new.txt"]), snapshot: snapshot)
        XCTAssertNil(result.failure)
        XCTAssertEqual(try GitClient.text(["show", "HEAD:a.txt"], in: root.path), "final work file")
        XCTAssertEqual(try GitClient.text(["show", ":keep.txt"], in: root.path), "keep staged\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("new.txt")), "leave this\n")
    }

    func testExternalCommitDuringReviewIsNotReportedAsOurCompletedCommit() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edit\n", "a.txt", root)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        _ = try GitClient.text(["commit", "--allow-empty", "-m", "external"], in: root.path)
        let result = CommitExecutor.execute(plan([["a.txt"]]), snapshot: snapshot)
        XCTAssertNotNil(result.failure); XCTAssertTrue(result.hashes.isEmpty)
    }

    func testHookAlteringCommitTreeStopsAndReportsCreatedCommit() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("edit\n", "a.txt", root); try write("b edit\n", "b.txt", root)
        try write("#!/bin/sh\ngit add b.txt\n", ".git/hooks/pre-commit", root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent(".git/hooks/pre-commit").path)
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["a.txt"], ["b.txt"]]), snapshot: snapshot)
        XCTAssertEqual(result.hashes.count, 1); XCTAssertNotNil(result.failure)
        XCTAssertEqual(try CommitSnapshot.readIndex(snapshot.indexPath), snapshot.indexData)
    }

    func testBinaryAndSymlinkNewFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data([0, 1, 2, 3, 255]).write(to: root.appendingPathComponent("binary.bin"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "missing-file")
        let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all)
        let result = CommitExecutor.execute(plan([["binary.bin", "link"]]), snapshot: snapshot)
        XCTAssertNil(result.failure); XCTAssertEqual(result.hashes.count, 1)
        XCTAssertEqual(try CommitProcess.git(["show", "HEAD:binary.bin"], in: root.path), Data([0, 1, 2, 3, 255]))
    }

    func testPreferencesPersistAndDiscoveryHonorsCustomInstallDirectory() throws {
        let suite = "MyGitCommitPrefs-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("omp", forKey: CommitPreferences.agentKey)
        defaults.set("/custom/omp", forKey: CommitPreferences.executableKey)
        defaults.set("/custom/SKILL.md", forKey: CommitPreferences.skillKey)
        defaults.set("custom-model", forKey: CommitPreferences.modelKey)
        let value = CommitPreferences(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(value.kind, .omp); XCTAssertEqual(value.executable, "/custom/omp")
        XCTAssertEqual(value.skillPath, "/custom/SKILL.md"); XCTAssertEqual(value.model, "custom-model")
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try write("#!/bin/sh\necho 'test-agent 1.0'\n", "codex", root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("codex").path)
        let found = AgentDiscovery.detect(directories: [root.path])
        XCTAssertEqual(found.count, 1); XCTAssertEqual(found.first?.version, "test-agent 1.0")
        XCTAssertTrue(AgentDiscovery.searchDirectories(home: "/example", path: "/custom/bin").contains("/custom/bin"))
        XCTAssertTrue(AgentDiscovery.searchDirectories(home: "/example", path: nil).contains("/example/.local/bin"))
    }
}
