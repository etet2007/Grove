import Foundation
import Combine

@MainActor final class DiffDiscardTargets: ObservableObject {
    private(set) var selectableRows: Set<Int> = []
    private(set) var hunkRows: [Int: Set<Int>] = [:]
    private var rowHunks: [Int: Int] = [:]

    func prepare(_ diff: SplitDiff) {
        selectableRows = []
        hunkRows = [:]
        rowHunks = [:]
        var hunk: Int?
        for row in diff.rows {
            if row.new?.kind == .heading { hunk = nil }
            if row.new?.kind == .hunk { hunk = row.id }
            if let hunk { rowHunks[row.id] = hunk }
            if row.old?.kind == .removed || row.new?.kind == .added {
                selectableRows.insert(row.id)
                if let hunk { hunkRows[hunk, default: []].insert(row.id) }
            }
        }
    }

    func lineTargets(for rowID: Int) -> Set<Int> {
        selectableRows.contains(rowID) ? [rowID] : []
    }

    func hunkTargets(for rowID: Int) -> Set<Int> {
        rowHunks[rowID].flatMap { hunkRows[$0] } ?? []
    }
}

struct DiffDiscardRequest: Identifiable {
    let id = UUID()
    let file: ChangedFile
    let checkoutPath: String
    let patch: String
    let selectedRows: Set<Int>
}

enum DiffDiscard {
    static var staleError: GitError {
        .command(AppLocalization.text("文件或暂存区已变化，请刷新后重新选择修改。"))
    }

    // Build the new working file from exact byte lines. The index stays intact.
    // A replacement row restores its old line in place of its new line; a pure
    // deletion inserts at the current new-side cursor, including EOF deletions.
    static func result(patch: String, baseline: Data, working: Data, selectedRows: Set<Int>) throws -> Data {
        guard String(data: baseline, encoding: .utf8) != nil,
              String(data: working, encoding: .utf8) != nil,
              !baseline.contains(0), !working.contains(0),
              patch.components(separatedBy: "diff --git ").count <= 2 else {
            throw GitError.command(AppLocalization.text("此文件不支持按块或行丢弃修改。"))
        }
        let rows = SplitDiff.parse(patch).rows
        let changedIDs = Set(rows.filter { $0.old?.kind == .removed || $0.new?.kind == .added }.map(\.id))
        guard !selectedRows.isEmpty, selectedRows.isSubset(of: changedIDs) else { throw staleError }
        let oldLines = byteLines(baseline)
        let newLines = byteLines(working)
        let newlineLines = newLines.filter { $0.last == 10 }
        let usesCRLF = !newlineLines.isEmpty && newlineLines.allSatisfy { $0.suffix(2) == Data([13, 10]) }
        var replacements: [Int: Data] = [:]
        var removed: Set<Int> = []
        var insertions: [Int: [Data]] = [:]
        var cursor = 0

        func checked(_ line: DiffLine, in bytes: [Data]) throws -> Data {
            guard let number = line.number, bytes.indices.contains(number - 1) else { throw staleError }
            let data = bytes[number - 1]
            var content = data
            if content.last == 10 { content.removeLast() }
            // Git may normalize CRLF in its text diff.
            let text = String(decoding: content, as: UTF8.self)
            guard text == line.text || (text.hasSuffix("\r") && String(text.dropLast()) == line.text) else { throw staleError }
            return data
        }

        for row in rows {
            if let line = row.new, line.kind == .hunk {
                let fields = line.text.split(separator: " ")
                guard fields.count >= 3 else { throw staleError }
                let range = fields[2].dropFirst().split(separator: ",")
                guard let start = range.first.flatMap({ Int($0) }) else { throw staleError }
                let count = range.count > 1 ? Int(range[1]) : 1
                cursor = count == 0 ? start : max(0, start - 1)
            }
            if let new = row.new, let number = new.number {
                _ = try checked(new, in: newLines)
                cursor = number - 1
            }
            if selectedRows.contains(row.id) {
                var original: Data?
                if let old = row.old, old.kind == .removed {
                    original = try checked(old, in: oldLines)
                    if usesCRLF, original?.last == 10, original?.suffix(2) != Data([13, 10]) {
                        original?.removeLast()
                        original?.append(contentsOf: [13, 10])
                    }
                }
                if let new = row.new, new.kind == .added, let number = new.number {
                    if let original { replacements[number - 1] = original }
                    else { removed.insert(number - 1) }
                } else if let original {
                    guard cursor >= 0, cursor <= newLines.count else { throw staleError }
                    insertions[cursor, default: []].append(original)
                }
            }
            if let new = row.new, let number = new.number { cursor = number }
        }
        var output: [Data] = []
        for index in 0...newLines.count {
            output.append(contentsOf: insertions[index] ?? [])
            if index < newLines.count, !removed.contains(index) {
                output.append(replacements[index] ?? newLines[index])
            }
        }
        // An unterminated old EOF line can become an interior line when other
        // additions remain. Keep those lines separated instead of concatenating.
        for index in output.indices.dropLast() where output[index].last != 10 {
            output[index].append(contentsOf: usesCRLF ? [13, 10] : [10])
        }
        return output.reduce(into: Data()) { $0.append($1) }
    }

    private static func byteLines(_ data: Data) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == 10 {
            let end = data.index(after: index)
            result.append(Data(data[start..<end]))
            start = end
        }
        if start < data.endIndex { result.append(Data(data[start..<data.endIndex])) }
        return result
    }

    static func apply(_ request: DiffDiscardRequest) throws {
        let file = request.file
        guard file.changeKind != .conflict else { throw staleError }
        let checkout = URL(fileURLWithPath: request.checkoutPath).resolvingSymlinksInPath()
        let target = checkout.appendingPathComponent(file.path).standardizedFileURL
        let resolved = target.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(checkout.path + "/"), resolved.path == target.path else {
            throw GitError.command(AppLocalization.text("此文件不支持按块或行丢弃修改。"))
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        if let type = attributes?[.type] as? FileAttributeType, type != .typeRegular { throw staleError }
        let entry = try GitClient.text(["--literal-pathspecs", "ls-files", "--stage", "-z", "--", file.path], in: checkout.path)
        let fields = entry.split(separator: "\t").first?.split(separator: " ") ?? []
        if file.isUntracked {
            guard entry.isEmpty, attributes != nil else { throw staleError }
        } else {
            guard fields.count == 3, fields[2] == "0", ["100644", "100755"].contains(String(fields[0])),
                  entry.split(separator: "\0").count == 1 else { throw staleError }
        }
        // Content filters and alternative encodings need their own round-trip
        // implementation; never overwrite their working representation as UTF-8.
        let attrs = try GitClient.text(["--literal-pathspecs", "check-attr", "-z", "filter", "working-tree-encoding", "--", file.path], in: checkout.path)
            .split(separator: "\0")
        for index in stride(from: 2, to: attrs.count, by: 3) where !["unspecified", "unset"].contains(String(attrs[index])) {
            throw GitError.command(AppLocalization.text("此文件不支持按块或行丢弃修改。"))
        }
        guard try GitClient.diff(for: file, in: checkout.path, mode: .unstaged) == request.patch else { throw staleError }
        let working = attributes == nil ? Data() : try Data(contentsOf: target)
        let baseline = file.isUntracked ? Data() : try GitClient.run(["cat-file", "blob", ":" + file.path], in: checkout.path)
        let output = try result(patch: request.patch, baseline: baseline, working: working, selectedRows: request.selectedRows)
        guard (attributes == nil ? !FileManager.default.fileExists(atPath: target.path) : try Data(contentsOf: target) == working),
              try GitClient.diff(for: file, in: checkout.path, mode: .unstaged) == request.patch else { throw staleError }
        if attributes != nil, !FileManager.default.isWritableFile(atPath: target.path) { throw staleError }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: target, options: .atomic)
        let permissions = attributes?[.posixPermissions] ?? NSNumber(value: fields.first == "100755" ? 0o755 : 0o644)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
    }
}
