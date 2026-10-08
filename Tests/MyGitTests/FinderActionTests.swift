import XCTest
@testable import MyGit

final class FinderActionTests: XCTestCase {
    func testExistingFileAndMissingHistoricalFileResolveWithinCheckout() throws {
        let checkout = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = checkout.appendingPathComponent("目录 with spaces")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: checkout) }
        let file = directory.appendingPathComponent("文件.txt")
        try Data("content".utf8).write(to: file)

        XCTAssertEqual(FinderAction.existingURL(for: file.path)?.path, file.path)
        XCTAssertEqual(FinderAction.existingURL(for: directory.path)?.path, directory.path)
        XCTAssertEqual(FinderAction.existingURL(for: directory.appendingPathComponent("deleted/file.txt").path)?.path,
                       directory.path)
    }
}
