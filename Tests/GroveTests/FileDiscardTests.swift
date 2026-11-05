import XCTest
@testable import Grove

final class FileDiscardTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveFileDiscard-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        _ = try GitClient.text(["config", "user.name", "Test"], in: root.path)
        _ = try GitClient.text(["config", "user.email", "test@example.invalid"], in: root.path)
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary.dat"))
        try "original".write(to: root.appendingPathComponent("文件 [x].txt"), atomically: true, encoding: .utf8)
        try "keep".write(to: root.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "initial"], in: root.path)
        return root
    }

    private func capture(_ root: URL, names: Set<String>) throws -> FileDiscardRequest {
        let files = try GitClient.changedFiles(in: root.path, repositoryID: UUID()).filter { names.contains($0.path) }
        XCTAssertEqual(files.count, names.count)
        return try FileDiscardRequest.capture([(root.path, files)])
    }

    func testBatchRestoresIndexBytesIncludingBinaryAndDeletedFilesAndDeletesUntracked() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appendingPathComponent("文件 [x].txt")
        try "staged".write(to: text, atomically: true, encoding: .utf8)
        _ = try GitClient.text(["add", "."], in: root.path)
        try "unstaged".write(to: text, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appendingPathComponent("binary.dat"))
        try "unselected".write(to: root.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        try "new".write(to: root.appendingPathComponent("-new.txt"), atomically: true, encoding: .utf8)
        let request = try capture(root, names: ["文件 [x].txt", "binary.dat", "-new.txt"])
        let index = try Data(contentsOf: URL(fileURLWithPath: request.checkouts[0].indexPath))
        try request.apply()
        XCTAssertEqual(try String(contentsOf: text), "staged")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("binary.dat")), Data([0, 1, 2]))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("keep.txt")), "unselected")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("-new.txt").path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: request.checkouts[0].indexPath)), index)
    }

    func testStaleFileRejectsWholeBatchBeforeFirstWrite() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0, 4]).write(to: root.appendingPathComponent("binary.dat"))
        let target = root.appendingPathComponent("文件 [x].txt")
        try "changed".write(to: target, atomically: true, encoding: .utf8)
        let request = try capture(root, names: ["binary.dat", "文件 [x].txt"])
        try "newer".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try request.apply())
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("binary.dat")), Data([0, 4]))
        XCTAssertEqual(try String(contentsOf: target), "newer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.checkouts[0].indexPath + ".lock"))
    }

    func testChangedIndexAndExistingLockAreRejected() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("文件 [x].txt")
        try "changed".write(to: target, atomically: true, encoding: .utf8)
        let request = try capture(root, names: ["文件 [x].txt"])
        let lock = URL(fileURLWithPath: request.checkouts[0].indexPath + ".lock")
        try Data("owned elsewhere".utf8).write(to: lock)
        XCTAssertThrowsError(try request.apply())
        XCTAssertEqual(try String(contentsOf: lock), "owned elsewhere")
        try FileManager.default.removeItem(at: lock)
        _ = try GitClient.text(["add", "."], in: root.path)
        XCTAssertThrowsError(try request.apply())
        XCTAssertEqual(try String(contentsOf: target), "changed")
    }

    func testSymlinkRestoredWithoutChangingItsDestination() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "keep.txt")
        _ = try GitClient.text(["add", "."], in: root.path)
        _ = try GitClient.text(["commit", "-m", "link"], in: root.path)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "文件 [x].txt")
        try capture(root, names: ["link"]).apply()
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "keep.txt")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("文件 [x].txt")), "original")
    }

    func testBranchChangeRejectsEvenWhenHeadIsUnchanged() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("keep.txt")
        try "changed".write(to: target, atomically: true, encoding: .utf8)
        let request = try capture(root, names: ["keep.txt"])
        _ = try GitClient.text(["switch", "-c", "other"], in: root.path)
        XCTAssertThrowsError(try request.apply())
        XCTAssertEqual(try String(contentsOf: target), "changed")
    }

    func testUnbornBranchAllowsRemovingUntrackedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GroveUnbornDiscard-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try GitClient.text(["init", "-b", "main"], in: root.path)
        try "new".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try capture(root, names: ["new.txt"]).apply()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
    }

    func testStaleSecondCheckoutLeavesFirstCheckoutUntouched() throws {
        let first = try fixture(), second = try fixture()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        for root in [first, second] {
            try "changed".write(to: root.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        }
        let targets = try [first, second].map { root in
            (checkout: root.path, files: try GitClient.changedFiles(in: root.path, repositoryID: UUID()))
        }
        let request = try FileDiscardRequest.capture(targets)
        try "newer".write(to: second.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try request.apply())
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("keep.txt")), "changed")
    }

    func testCheckoutEscapeViaParentSymlinkIsRejected() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root.deletingLastPathComponent())
        let file = ChangedFile(repositoryID: UUID(), path: "escape/outside", indexStatus: "?", worktreeStatus: "?", isUntracked: true)
        XCTAssertThrowsError(try FileDiscardRequest.capture([(root.path, [file])]))
    }
}
