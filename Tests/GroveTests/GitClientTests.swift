import XCTest
@testable import Grove

final class GitClientTests: XCTestCase {
    func testMergeCommitShowsNormalDiffAgainstFirstParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveMergeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String { try GitClient.text(args, in: root.path) }
        func write(_ value: String) throws {
            try value.write(to: root.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Grove Test"])
        _ = try git(["config", "user.email", "grove@example.invalid"])
        try write("base\n")
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "base"])
        _ = try git(["switch", "-c", "feature"])
        try write("feature\n")
        _ = try git(["commit", "-am", "feature"])
        _ = try git(["switch", "main"])
        try write("main\n")
        _ = try git(["commit", "-am", "main"])
        // Resolve a conflict to a third value, forcing Git's default combined diff.
        XCTAssertThrowsError(try git(["merge", "feature"]))
        try write("resolved\n")
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "merge"])
        let commit = try XCTUnwrap(GitClient.commits(in: root.path, repositoryID: UUID(), limit: 1).first)
        XCTAssertEqual(commit.parents, try git(["rev-list", "--parents", "-n", "1", "HEAD"])
            .split(whereSeparator: { $0.isWhitespace }).dropFirst().map(String.init))
        let history = try GitClient.commits(in: root.path, repositoryID: commit.repositoryID, limit: 20)
        let positions = Dictionary(uniqueKeysWithValues: history.enumerated().map { ($0.element.hash, $0.offset) })
        for (index, item) in history.enumerated() {
            for parent in item.parents {
                if let parentIndex = positions[parent] { XCTAssertGreaterThan(parentIndex, index) }
            }
        }
        let output = try GitClient.show(commit, in: root.path)
        XCTAssertFalse(output.contains("diff --cc"))
        let patch = CommitPatch.parse(output)
        XCTAssertTrue(patch.isMerge)
        let file = try XCTUnwrap(patch.files.first)
        XCTAssertEqual(file.path, "manifest.txt")
        XCTAssertTrue(file.diff.hasChanges)
        XCTAssertTrue(file.patch.contains("-main"))
        XCTAssertTrue(file.patch.contains("+resolved"))
        XCTAssertFalse(file.patch.contains("-feature"))

        // A clean merge also exposes incoming changes, even though combined diff is empty.
        _ = try git(["switch", "feature"])
        try "incoming\n".write(to: root.appendingPathComponent("incoming.txt"), atomically: true, encoding: .utf8)
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "incoming"])
        _ = try git(["switch", "main"])
        _ = try git(["merge", "--no-ff", "feature", "-m", "clean merge"])
        let clean = try XCTUnwrap(GitClient.commits(in: root.path, repositoryID: UUID(), limit: 1).first)
        let cleanPatch = CommitPatch.parse(try GitClient.show(clean, in: root.path))
        XCTAssertTrue(cleanPatch.isMerge)
        XCTAssertEqual(cleanPatch.files.map(\.path), ["incoming.txt"])
        XCTAssertEqual(cleanPatch.files.first?.change, .added)
    }

    func testHistoryUsesCommitterAndCommitTimeRatherThanAuthorMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveCommitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "commit", "--allow-empty", "-m", "different metadata"]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_AUTHOR_NAME"] = "Original Author"
        environment["GIT_AUTHOR_EMAIL"] = "author@example.invalid"
        environment["GIT_AUTHOR_DATE"] = "2020-01-01T00:00:00+0000"
        environment["GIT_COMMITTER_NAME"] = "Actual Committer"
        environment["GIT_COMMITTER_EMAIL"] = "committer@example.invalid"
        environment["GIT_COMMITTER_DATE"] = "2024-02-03T04:05:06+0000"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let commit = try XCTUnwrap(GitClient.commits(in: root.path, repositoryID: UUID(), limit: 1).first)
        XCTAssertEqual(commit.committer, "Actual Committer")
        XCTAssertEqual(commit.date, ISO8601DateFormatter().date(from: "2024-02-03T04:05:06Z"))
    }

    func testWorktreeDiscoveryStatusAndDiff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveTests-\(UUID().uuidString)")
        let main = root.appendingPathComponent("main")
        let feature = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func git(_ arguments: [String], at path: URL = main) throws -> String {
            try GitClient.text(arguments, in: path.path)
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Grove Test"])
        _ = try git(["config", "user.email", "grove@example.invalid"])
        try "first\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "initial"])
        _ = try git(["worktree", "add", "-b", "feature/test", feature.path])

        let trees = try GitClient.worktrees(in: main.path)
        XCTAssertEqual(trees.count, 2)
        XCTAssertTrue(trees.contains(where: { $0.isPrimary && $0.branch == "main" }))
        XCTAssertTrue(trees.contains(where: { !$0.isPrimary && $0.branch == "feature/test" }))

        let tracked = feature.appendingPathComponent("tracked.txt")
        try "first\nsecond\n".write(to: tracked, atomically: true, encoding: .utf8)
        _ = try git(["add", "tracked.txt"], at: feature)
        try "first\nsecond\nthird\n".write(to: tracked, atomically: true, encoding: .utf8)
        try "new\n".write(to: feature.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        let files = try GitClient.changedFiles(in: feature.path, repositoryID: UUID())
        let changed = try XCTUnwrap(files.first(where: { $0.path == "tracked.txt" }))
        XCTAssertTrue(changed.hasStaged)
        XCTAssertTrue(changed.hasUnstaged)
        XCTAssertEqual(changed.changeKind, .modified)
        XCTAssertEqual(changed.stats?.additions, 2)
        XCTAssertEqual(changed.stats?.deletions, 0)
        let untracked = try XCTUnwrap(files.first(where: { $0.path == "new.txt" }))
        XCTAssertEqual(untracked.changeKind, .added)
        XCTAssertEqual(untracked.stats?.additions, 1)
        XCTAssertTrue(files.contains(where: { $0.path == "new.txt" && $0.isUntracked }))
        XCTAssertTrue(try GitClient.diff(for: changed, in: feature.path, mode: .unstaged).contains("+third"))
        XCTAssertTrue(try GitClient.diff(for: changed, in: feature.path, mode: .staged).contains("+second"))
        XCTAssertEqual(try GitClient.commits(in: feature.path, repositoryID: UUID(), limit: 10).first?.subject, "initial")
    }

    func testNumstatHandlesRenameTabsAndBinaryFiles() {
        let data = Data("3\t2\tfile\twith-tab.txt\0".utf8) +
            Data("0\t0\t\0old name.txt\0new name.txt\0-\t-\tasset.png\0".utf8)
        let stats = GitClient.parseNumstat(data)
        XCTAssertEqual(stats["file\twith-tab.txt"], FileChangeStats(additions: 3, deletions: 2))
        XCTAssertEqual(stats["new name.txt"], FileChangeStats(additions: 0, deletions: 0))
        XCTAssertNil(stats["old name.txt"])
        XCTAssertEqual(stats["asset.png"]?.isBinary, true)
    }

    func testChangeBadgesDescribeStatusInsteadOfRepository() {
        func kind(_ status: String) -> FileChangeKind {
            let chars = Array(status)
            return ChangedFile(repositoryID: UUID(), path: "file", indexStatus: chars[0],
                               worktreeStatus: chars[1], isUntracked: status == "??").changeKind
        }
        XCTAssertEqual(kind("??"), .added)
        XCTAssertEqual(kind("A "), .added)
        XCTAssertEqual(kind(" M"), .modified)
        XCTAssertEqual(kind("MM"), .modified)
        XCTAssertEqual(kind(" D"), .deleted)
        XCTAssertEqual(kind("AD"), .deleted)
        XCTAssertEqual(kind("R "), .renamed)
        for status in ["DD", "AU", "UD", "UA", "DU", "AA", "UU"] {
            XCTAssertEqual(kind(status), .conflict)
        }
    }

    func testGroupSelectsMatchingBranchThenPrimaryUnlessOverridden() {
        let repositoryID = UUID()
        let primary = Worktree(path: "/main", branch: "main", head: "a", isPrimary: true, isDetached: false)
        let feature = Worktree(path: "/feature", branch: "feature", head: "b", isPrimary: false, isDetached: false)
        let other = Worktree(path: "/other", branch: "other", head: "c", isPrimary: false, isDetached: false)
        var group = WorktreeGroup(name: "feature", branch: "feature")
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, feature, other]), feature)
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, other]), primary)
        group.selections[repositoryID] = other.path
        XCTAssertEqual(WorktreeSelection.resolve(group: group, repositoryID: repositoryID, worktrees: [primary, feature, other]), other)
    }

    func testImagePreviewReadsCorrectVersionsForDeletionAndStaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveImageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "asset.webp"
        let url = root.appendingPathComponent(path)
        let original = Data([0, 1, 2, 255])
        let replacement = Data([0, 1, 3, 255])
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Grove Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "grove@example.invalid"], in: root.path)
        try original.write(to: url)
        _ = try GitClient.text(["add", path], in: root.path)
        _ = try GitClient.text(["commit", "-m", "image"], in: root.path)

        try replacement.write(to: url)
        var file = try XCTUnwrap(GitClient.changedFiles(in: root.path, repositoryID: UUID()).first)
        var preview = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: .unstaged))
        XCTAssertEqual(preview.old.data, original)
        XCTAssertEqual(preview.new.data, replacement)

        _ = try GitClient.text(["add", path], in: root.path)
        try FileManager.default.removeItem(at: url)
        file = try XCTUnwrap(GitClient.changedFiles(in: root.path, repositoryID: UUID()).first)
        preview = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: .unstaged))
        XCTAssertEqual(preview.old.data, replacement)
        XCTAssertNil(preview.new.data)
        preview = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: .staged))
        XCTAssertEqual(preview.old.data, original)
        XCTAssertEqual(preview.new.data, replacement)
        preview = try XCTUnwrap(GitClient.imagePreview(for: file, in: root.path, mode: .all))
        XCTAssertEqual(preview.old.data, original)
        XCTAssertNil(preview.new.data)
    }

    func testManualWorktreeChoiceSurvivesConfigurationRoundTrip() throws {
        let repositoryID = UUID()
        var group = WorktreeGroup(name: "feature", branch: "feature")
        group.selections[repositoryID] = "/worktrees/feature"
        var project = Project(name: "Android")
        project.worktreeGroups = [group]
        let original = Configuration(projects: [project], selectedProjectID: project.id,
                                     selectedWorktreeGroupID: group.id)
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.projects[0].worktreeGroups[0].selections[repositoryID], "/worktrees/feature")
        XCTAssertEqual(restored.selectedWorktreeGroupID, group.id)
    }

    func testMergeRequestURLSupportsGitLabRemotesAndEncodesBranch() {
        let expected = "http://gitlab.example.com/team/app/-/merge_requests/new?merge_request%5Bsource_branch%5D=feature/login"
        XCTAssertEqual(GitClient.mergeRequestURL(remoteURL: "git@gitlab.example.com:team/app.git", branch: "feature/login")?.absoluteString, expected)
        XCTAssertEqual(GitClient.mergeRequestURL(remoteURL: "https://user:secret@gitlab.example.com/team/app.git", branch: "feature/login")?.absoluteString, expected)
        XCTAssertEqual(GitClient.mergeRequestURL(remoteURL: "ssh://git@gitlab.example.com:2222/team/app.git", branch: "feature/login")?.absoluteString, expected)
        XCTAssertEqual(GitClient.mergeRequestURL(remoteURL: "http://gitlab.example.com/team/app.git", branch: "feature/login")?.absoluteString, expected)
        XCTAssertEqual(GitClient.mergeRequestURL(remoteURL: "http://gitlab.example.com:8080/team/app.git", branch: "feature/login")?.port, 8080)
        XCTAssertNil(GitClient.mergeRequestURL(remoteURL: "/tmp/team/app", branch: "feature/login"))
    }

    func testMergeRequestURLUsesSelectedBranchRemote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveMRTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "feature/login"], in: root.path)
        _ = try GitClient.text(["remote", "add", "origin", "git@gitlab.example.com:team/default.git"], in: root.path)
        _ = try GitClient.text(["remote", "add", "review", "https://gitlab.example.com/team/app.git"], in: root.path)
        _ = try GitClient.text(["config", "branch.feature/login.remote", "review"], in: root.path)
        XCTAssertEqual(GitClient.mergeRequestURL(in: root.path, branch: "feature/login")?.host, "gitlab.example.com")
        XCTAssertEqual(GitClient.mergeRequestURL(in: root.path, branch: "feature/login")?.path, "/team/app/-/merge_requests/new")
    }
}
