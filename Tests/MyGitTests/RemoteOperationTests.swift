import XCTest
@testable import MyGit

final class RemoteOperationTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitRemoteTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bare = root.appendingPathComponent("remote.git"), local = root.appendingPathComponent("local"), other = root.appendingPathComponent("other")
        _ = try CommitProcess.git(["init", "--bare", "-b", "main", bare.path], in: root.path)
        _ = try CommitProcess.git(["clone", bare.path, local.path], in: root.path)
        for repo in [local] {
            _ = try CommitProcess.git(["config", "user.name", "Test"], in: repo.path)
            _ = try CommitProcess.git(["config", "user.email", "test@example.invalid"], in: repo.path)
        }
        try commit(local, "initial")
        _ = try CommitProcess.git(["push", "-u", "origin", "main"], in: local.path)
        _ = try CommitProcess.git(["clone", bare.path, other.path], in: root.path)
        _ = try CommitProcess.git(["config", "user.name", "Test"], in: other.path)
        _ = try CommitProcess.git(["config", "user.email", "test@example.invalid"], in: other.path)
        return (root, local, other)
    }
    private func commit(_ repo: URL, _ content: String) throws {
        try content.write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = try CommitProcess.git(["add", "file.txt"], in: repo.path)
        _ = try CommitProcess.git(["-c", "commit.gpgsign=false", "commit", "-m", content], in: repo.path)
    }
    private func request(_ repo: URL, _ operation: RemoteOperation, branch: String = "main", upstream: Bool = false) throws -> RemoteRequest {
        RemoteRequest(checkout: repo.path, configuration: try .read(in: repo.path), operation: operation,
                      remote: "origin", branch: branch, setUpstream: upstream)
    }
    func testFetchDoesNotChangeLocalHeadAndPullFastForwards() throws {
        let (root, local, other) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = try CommitProcess.gitText(["rev-parse", "HEAD"], in: local.path)
        try commit(other, "remote update")
        _ = try CommitProcess.git(["push", "origin", "main"], in: other.path)
        var activity: [CommitActivity] = []
        try request(local, .fetch).execute(progress: { activity.append($0) })
        XCTAssertTrue(activity.contains { $0.kind == .output && !$0.detail.isEmpty })
        XCTAssertEqual(try CommitProcess.gitText(["rev-parse", "HEAD"], in: local.path), before)
        XCTAssertNotEqual(try CommitProcess.gitText(["rev-parse", "origin/main"], in: local.path), before)
        try request(local, .pull).execute()
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("file.txt")), "remote update")
    }
    func testPullRefusesDirtyAndDivergedBranchesWithoutStashOrMerge() throws {
        let (root, local, other) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try "dirty".write(to: local.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try request(local, .pull).execute())
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("file.txt")), "dirty")
        try commit(local, "local change")
        let head = try CommitProcess.gitText(["rev-parse", "HEAD"], in: local.path)
        try commit(other, "remote change")
        _ = try CommitProcess.git(["push", "origin", "main"], in: other.path)
        _ = try CommitProcess.git(["config", "pull.rebase", "true"], in: local.path)
        _ = try CommitProcess.git(["config", "merge.autostash", "true"], in: local.path)
        XCTAssertThrowsError(try request(local, .pull).execute())
        XCTAssertEqual(try CommitProcess.gitText(["rev-parse", "HEAD"], in: local.path), head)
        XCTAssertEqual(try CommitProcess.gitText(["stash", "list"], in: local.path), "")
    }
    func testPushOnlySelectedBranchAndCreatesUpstream() throws {
        let (root, local, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try CommitProcess.git(["switch", "-c", "feature/test"], in: local.path)
        try commit(local, "feature")
        _ = try CommitProcess.git(["branch", "unselected"], in: local.path)
        _ = try CommitProcess.git(["config", "push.default", "matching"], in: local.path)
        _ = try CommitProcess.git(["config", "remote.origin.push", "+refs/heads/*:refs/heads/*"], in: local.path)
        try request(local, .push, branch: "feature/test", upstream: true).execute()
        let refs = try CommitProcess.gitText(["ls-remote", "--heads", "origin"], in: local.path)
        XCTAssertTrue(refs.contains("refs/heads/feature/test")); XCTAssertFalse(refs.contains("unselected"))
        XCTAssertEqual(try RemoteConfiguration.read(in: local.path).upstreamBranch, "feature/test")
    }
    func testStaleConfigurationInvalidBranchAndSharedWorktreeLock() throws {
        let (root, local, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let stale = try request(local, .push)
        try commit(local, "new head")
        XCTAssertThrowsError(try stale.execute())
        for branch in ["", "main:other", "bad branch", "../bad"] {
            XCTAssertThrowsError(try request(local, .push, branch: branch).execute())
        }
        let linked = root.appendingPathComponent("linked")
        _ = try CommitProcess.git(["worktree", "add", "-b", "linked", linked.path], in: local.path)
        XCTAssertTrue(CheckoutOperationLock.acquire(local.path))
        defer { CheckoutOperationLock.release(local.path) }
        XCTAssertFalse(CheckoutOperationLock.acquire(linked.path))
        XCTAssertThrowsError(try request(linked, .fetch).execute())
    }
    func testQuickOperationsUseExactUpstreamAndRefuseGuessing() throws {
        let (root, local, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try CommitProcess.git(["config", "branch.main.merge", "refs/heads/release/target"], in: local.path)
        let configuration = try RemoteConfiguration.read(in: local.path)
        for operation in [RemoteOperation.pull, .push] {
            let request = try RemoteRequest.quick(checkout: local.path, configuration: configuration, operation: operation)
            XCTAssertEqual(request.remote, "origin")
            XCTAssertEqual(request.branch, "release/target")
            XCTAssertFalse(request.setUpstream)
        }
        _ = try CommitProcess.git(["config", "--unset", "branch.main.remote"], in: local.path)
        let noUpstream = try RemoteConfiguration.read(in: local.path)
        XCTAssertThrowsError(try RemoteRequest.quick(checkout: local.path, configuration: noUpstream, operation: .pull))
        XCTAssertThrowsError(try RemoteRequest.quick(checkout: local.path, configuration: noUpstream, operation: .push))
        XCTAssertEqual(try RemoteRequest.quick(checkout: local.path, configuration: noUpstream, operation: .fetch).remote, "origin")
    }
    func testBranchStatusTracksAheadBehindDivergenceAndMissingUpstreamLocally() throws {
        let (root, local, other) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let synced = try RemoteBranchStatus.read(in: local.path, branch: "main")
        XCTAssertEqual(synced.ahead, 0); XCTAssertEqual(synced.behind, 0)
        try commit(other, "remote update")
        _ = try CommitProcess.git(["push", "origin", "main"], in: other.path)
        // Nothing contacts the remote during a local status read.
        XCTAssertEqual(try RemoteBranchStatus.read(in: local.path, branch: "main").behind, 0)
        try request(local, .fetch).execute()
        XCTAssertEqual(try RemoteBranchStatus.read(in: local.path, branch: "main").behind, 1)
        try commit(local, "local update")
        let diverged = try RemoteBranchStatus.read(in: local.path, branch: "main")
        XCTAssertEqual(diverged.ahead, 1); XCTAssertEqual(diverged.behind, 1); XCTAssertTrue(diverged.diverged)
        XCTAssertEqual(diverged.pending(.fetch), nil)
        _ = try CommitProcess.git(["update-ref", "-d", "refs/remotes/origin/main"], in: local.path)
        let missing = try RemoteBranchStatus.read(in: local.path, branch: "main")
        XCTAssertTrue(missing.missing); XCTAssertNil(missing.ahead); XCTAssertNil(missing.behind)
        _ = try CommitProcess.git(["config", "--unset", "branch.main.remote"], in: local.path)
        XCTAssertFalse(try RemoteBranchStatus.read(in: local.path, branch: "main").hasRemoteUpstream)
        XCTAssertFalse(try RemoteBranchStatus.read(in: local.path, branch: nil).hasRemoteUpstream)
    }

    func testRemoteOutputRedactsURLCredentials() {
        let text = CommitOutputText.clean("https://alice:password@example.com/repo https://token@example.com/repo")
        XCTAssertFalse(text.contains("password")); XCTAssertFalse(text.contains("token"))
        XCTAssertTrue(text.contains("example.com/repo"))
    }
    func testNonFastForwardPushNeverForcesRemote() throws {
        let (root, local, other) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try commit(other, "remote")
        _ = try CommitProcess.git(["push", "origin", "main"], in: other.path)
        let remoteHead = try CommitProcess.gitText(["rev-parse", "HEAD"], in: other.path)
        try commit(local, "local")
        XCTAssertThrowsError(try request(local, .push).execute())
        XCTAssertTrue(try CommitProcess.gitText(["ls-remote", "origin", "refs/heads/main"], in: local.path).hasPrefix(remoteHead))
    }
}
