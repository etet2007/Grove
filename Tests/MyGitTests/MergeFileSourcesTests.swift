import XCTest
@testable import MyGit

final class MergeFileSourcesTests: XCTestCase {
    func testSourcesExcludeCurrentBranchAndUnrelatedFilesAndHandleRenameAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitSources-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) throws -> String { try GitClient.text(args, in: root.path) }
        func write(_ name: String, _ text: String) throws {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func commit(_ author: String, _ subject: String) throws {
            _ = try git(["add", "."])
            _ = try git(["commit", "--author", "\(author) <\(author)@example.invalid>", "-m", subject])
        }
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "Merge Operator"])
        _ = try git(["config", "user.email", "operator@example.invalid"])
        try write("shared.txt", "base\n")
        try write("deleted.txt", "delete me\n")
        try write("old.txt", "rename me\n")
        try commit("Base", "base")
        _ = try git(["switch", "-c", "incoming"])
        try write("shared.txt", "Alice\n")
        try commit("Alice", "first change")
        try write("shared.txt", "Alice\nBob\n")
        try commit("Bob", "second change")
        _ = try git(["mv", "old.txt", "[资料].txt"])
        try commit("Alice", "rename file")
        _ = try git(["rm", "deleted.txt"])
        try commit("Bob", "delete file")
        try write("unrelated.txt", "unrelated\n")
        try commit("Charlie", "unrelated file")
        _ = try git(["switch", "main"])
        try write("own.txt", "local\n")
        try commit("Local", "current branch only")
        _ = try git(["merge", "--no-ff", "--no-commit", "incoming"])
        try write("merge-only.txt", "written during merge\n")
        _ = try git(["add", "."])
        _ = try git(["commit", "-m", "merge incoming"])
        let merge = try XCTUnwrap(GitClient.commits(in: root.path, repositoryID: UUID(), limit: 1).first)
        let patch = CommitPatch.parse(try GitClient.show(merge, in: root.path))
        let shared = try XCTUnwrap(patch.files.first { $0.path == "shared.txt" })
        let sources = try GitClient.mergeSources(commit: merge.hash, file: shared, in: root.path)
        XCTAssertEqual(Set(sources.map(\.author)), ["Alice", "Bob"])
        XCTAssertEqual(Set(sources.map(\.subject)), ["first change", "second change"])
        XCTAssertTrue(sources.allSatisfy { !$0.email.isEmpty && $0.hash.count == 40 })
        let renamed = try XCTUnwrap(patch.files.first { $0.path == "[资料].txt" })
        XCTAssertEqual(renamed.oldPath, "old.txt")
        XCTAssertEqual(try GitClient.mergeSources(commit: merge.hash, file: renamed, in: root.path).map(\.subject), ["rename file"])
        let deleted = try XCTUnwrap(patch.files.first { $0.path == "deleted.txt" })
        XCTAssertEqual(try GitClient.mergeSources(commit: merge.hash, file: deleted, in: root.path).map(\.subject), ["delete file"])
        let mergeOnly = try XCTUnwrap(patch.files.first { $0.path == "merge-only.txt" })
        XCTAssertTrue(try GitClient.mergeSources(commit: merge.hash, file: mergeOnly, in: root.path).isEmpty)
        XCTAssertTrue(try GitClient.mergeSources(commit: sources[0].hash, file: shared, in: root.path).isEmpty)
        XCTAssertThrowsError(try GitClient.mergeSources(commit: String(repeating: "0", count: 40), file: shared, in: root.path))
    }
}
