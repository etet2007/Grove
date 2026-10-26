import XCTest
import CryptoKit
@testable import MyGit

final class AppUpdateTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitUpdateTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func manifest(_ data: Data, build: Int = 2) -> AppUpdateManifest {
        AppUpdateManifest(version: "0.2.0", build: build,
                          sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), notes: "Test release")
    }

    private func publish(_ directory: URL, bytes: Data, build: Int) throws {
        try bytes.write(to: directory.appendingPathComponent("MyGit.zip"))
        try JSONEncoder().encode(manifest(bytes, build: build)).write(to: directory.appendingPathComponent("latest.json"))
        _ = try CommitProcess.git(["add", "latest.json", "MyGit.zip"], in: directory.path)
        _ = try CommitProcess.git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "release"], in: directory.path)
    }

    func testReadLatestCommitAndRewrittenReleaseHistory() throws {
        let repo = try temporaryDirectory()
        _ = try CommitProcess.git(["init", "-b", "main"], in: repo.path)
        try publish(repo, bytes: Data("old app".utf8), build: 2)
        let first = try XCTUnwrap(AppUpdateService.check(repository: repo.absoluteString, branch: "main", currentBuild: 1))
        defer { try? FileManager.default.removeItem(at: first.directory) }
        XCTAssertEqual(try Data(contentsOf: first.archive), Data("old app".utf8))
        XCTAssertNil(try AppUpdateService.check(repository: repo.absoluteString, branch: "main", currentBuild: 2))
        XCTAssertNil(try AppUpdateService.check(repository: repo.absoluteString, branch: "main", currentBuild: 99))
        _ = try CommitProcess.git(["checkout", "--orphan", "replacement"], in: repo.path)
        try publish(repo, bytes: Data("new app".utf8), build: 3)
        _ = try CommitProcess.git(["branch", "-M", "main"], in: repo.path)
        let second = try XCTUnwrap(AppUpdateService.check(repository: repo.absoluteString, branch: "main", currentBuild: 2))
        defer { try? FileManager.default.removeItem(at: second.directory) }
        XCTAssertEqual(second.manifest.build, 3)
        XCTAssertEqual(try Data(contentsOf: second.archive), Data("new app".utf8))
        // The first prepared update is pinned, regardless of subsequent remote publication.
        XCTAssertEqual(try Data(contentsOf: first.archive), Data("old app".utf8))
    }

    func testRejectCorruptArchiveAndUnsafeSource() throws {
        let data = Data("app".utf8)
        XCTAssertNoThrow(try AppUpdateService.verifyArchive(data, manifest: manifest(data)))
        XCTAssertThrowsError(try AppUpdateService.verifyArchive(Data("changed".utf8), manifest: manifest(data)))
        XCTAssertThrowsError(try AppUpdateManifest(version: "1", build: 1, sha256: "bad", notes: "").validate())
        for source in ["", "--upload-pack=evil", "ext::evil", "http://example.com/repo"] {
            XCTAssertThrowsError(try AppUpdateService.check(repository: source, branch: "main", currentBuild: 1))
        }
        let repo = try temporaryDirectory()
        _ = try CommitProcess.git(["init", "-b", "main"], in: repo.path)
        try publish(repo, bytes: data, build: 2)
        try Data("corrupt".utf8).write(to: repo.appendingPathComponent("MyGit.zip"))
        _ = try CommitProcess.git(["add", "."], in: repo.path)
        _ = try CommitProcess.git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "corrupt"], in: repo.path)
        XCTAssertThrowsError(try AppUpdateService.check(repository: repo.absoluteString, branch: "main", currentBuild: 1))
        XCTAssertThrowsError(try AppUpdateService.check(repository: repo.absoluteString, branch: "missing", currentBuild: 1))
    }

    func testUpdateReservationExcludesGitWrites() throws {
        let repo = try temporaryDirectory()
        _ = try CommitProcess.git(["init"], in: repo.path)
        XCTAssertTrue(CheckoutOperationLock.acquire(repo.path))
        XCTAssertFalse(CheckoutOperationLock.beginAppUpdate())
        CheckoutOperationLock.release(repo.path)
        XCTAssertTrue(CheckoutOperationLock.beginAppUpdate())
        defer { CheckoutOperationLock.endAppUpdate() }
        XCTAssertFalse(CheckoutOperationLock.acquire(repo.path))
        XCTAssertFalse(CheckoutOperationLock.beginAppUpdate())
    }

    func testRejectUnsignedApplication() throws {
        let root = try temporaryDirectory()
        let app = root.appendingPathComponent("MyGit.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertThrowsError(try AppUpdateService.verifySignature(app: app, currentApp: app))
    }
    private func signedFixture(in root: URL) throws -> URL {
        let app = root.appendingPathComponent("MyGit.app")
        let contents = app.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/MyGit")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
        let info = ["CFBundleIdentifier": "dev.mygit.update-test", "CFBundleExecutable": "MyGit",
                    "CFBundlePackageType": "APPL", "CFBundleVersion": "2", "CFBundleShortVersionString": "0.2.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let result = try CommitProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], in: root.path)
        XCTAssertEqual(result.status, 0, result.diagnostic)
        return app
    }

    func testPrepareSignedBundleAndRejectWrongVersionAndSymlinks() throws {
        let root = try temporaryDirectory()
        let app = try signedFixture(in: root)
        func package(build: Int = 2) throws -> PreparedAppUpdate {
            let staging = try temporaryDirectory()
            let zip = staging.appendingPathComponent("MyGit.zip")
            let result = try CommitProcess.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path], in: root.path)
            XCTAssertEqual(result.status, 0)
            return PreparedAppUpdate(directory: staging, manifest: manifest(try Data(contentsOf: zip), build: build))
        }
        let prepared = try package()
        XCTAssertNoThrow(try AppUpdateService.prepareInstallation(prepared, currentApp: app))
        XCTAssertThrowsError(try AppUpdateService.prepareInstallation(try package(build: 3), currentApp: app))
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("escape").path, withDestinationPath: "/tmp")
        XCTAssertThrowsError(try AppUpdateService.prepareInstallation(try package(), currentApp: app))
        try FileManager.default.removeItem(at: app.appendingPathComponent("escape"))
        try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/MacOS/MyGit"))
        XCTAssertThrowsError(try AppUpdateService.verifySignature(app: app, currentApp: app))
    }

    func testInstallerFailureLeavesExistingAppUntouched() throws {
        let root = try temporaryDirectory()
        let target = try signedFixture(in: root)
        let original = try Data(contentsOf: target.appendingPathComponent("Contents/Info.plist"))
        let update = root.appendingPathComponent("update")
        let source = update.appendingPathComponent("MyGit.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let result = try CommitProcess.run("/bin/sh", [project.appendingPathComponent("scripts/install-update.sh").path,
            "999999", source.path, target.path, update.path, root.appendingPathComponent("logs").path], in: root.path)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.path))
        XCTAssertNoThrow(try AppUpdateService.verifySignature(app: target, currentApp: target))
    }

    func testInstallerReplacesAndLaunchesTemporaryApplication() throws {
        let root = try temporaryDirectory()
        let target = try signedFixture(in: root)
        let update = root.appendingPathComponent("update")
        try FileManager.default.createDirectory(at: update, withIntermediateDirectories: true)
        let source = try signedFixture(in: update)
        let info = source.appendingPathComponent("Contents/Info.plist")
        var values = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: String])
        values["CFBundleVersion"] = "3"
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: info)
        let sign = try CommitProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", source.path], in: root.path)
        XCTAssertEqual(sign.status, 0)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let result = try CommitProcess.run("/bin/sh", [project.appendingPathComponent("scripts/install-update.sh").path,
            "999999", source.path, target.path, update.path, root.appendingPathComponent("logs").path], in: root.path)
        let log = try String(contentsOf: root.appendingPathComponent("logs/update.log"))
        XCTAssertEqual(result.status, 0, log)
        let installed = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: String])
        XCTAssertEqual(installed["CFBundleVersion"], "3", log)
        XCTAssertFalse(FileManager.default.fileExists(atPath: update.path))
    }

}
