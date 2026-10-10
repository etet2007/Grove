import Foundation

struct CommitFilePatch: Identifiable {
    enum Change: String {
        case added = "新增", deleted = "删除", modified = "修改", renamed = "重命名", copied = "复制"
        var badge: String {
            switch self {
            case .added: "A"
            case .deleted: "D"
            case .modified: "M"
            case .renamed: "R"
            case .copied: "C"
            }
        }
    }

    let id: Int
    let path: String
    let oldPath: String?
    let change: Change
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let patch: String
    let diff: SplitDiff
    var name: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }

    var binarySummaryTitle: String? {
        guard isBinary else { return nil }
        let image = GitClient.isImagePath(path)
        switch change {
        case .added: return image ? "新增图片" : "新增二进制文件"
        case .deleted: return image ? "图片已删除" : "二进制文件已删除"
        case .modified: return image ? "图片已修改" : "二进制文件已修改"
        case .renamed: return image ? "图片已移动或重命名" : "二进制文件已移动或重命名"
        case .copied: return image ? "图片已复制" : "二进制文件已复制"
        }
    }

    // Only replace metadata-only renames; preserve patches containing content or mode changes.
    var isPureRename: Bool {
        let lines = patch.components(separatedBy: "\n").filter { !$0.isEmpty }
        return change == .renamed && oldPath != nil
            && lines.contains("similarity index 100%")
            && lines.contains { $0.hasPrefix("rename from ") }
            && lines.contains { $0.hasPrefix("rename to ") }
            && lines.allSatisfy {
                $0.hasPrefix("diff --git ") || $0 == "similarity index 100%"
                    || $0.hasPrefix("rename from ") || $0.hasPrefix("rename to ")
            }
    }
}

struct CommitPatch {
    let files: [CommitFilePatch]
    let fullDiff: SplitDiff
    let isMerge: Bool
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    static func parse(_ text: String, prepareDiff: Bool = true) -> CommitPatch {
        let lines = text.components(separatedBy: "\n")
        let starts = lines.indices.filter { lines[$0].hasPrefix("diff --git ") }
        let files = starts.enumerated().map { index, start -> CommitFilePatch in
            let end = index + 1 < starts.count ? starts[index + 1] : lines.count
            let section = Array(lines[start..<end])
            let paths = headerPaths(String(lines[start].dropFirst(11)))
            var oldPath = paths.first ?? ""
            var path = paths.last ?? ""
            var change = CommitFilePatch.Change.modified
            var additions = 0
            var deletions = 0
            var inHunk = false
            var binary = false
            for line in section.dropFirst() {
                if line.hasPrefix("new file mode ") { change = .added }
                else if line.hasPrefix("deleted file mode ") { change = .deleted }
                else if line.hasPrefix("rename from ") {
                    change = .renamed; oldPath = decodePath(String(line.dropFirst(12)))
                } else if line.hasPrefix("rename to ") { path = decodePath(String(line.dropFirst(10))) }
                else if line.hasPrefix("copy from ") {
                    change = .copied; oldPath = decodePath(String(line.dropFirst(10)))
                } else if line.hasPrefix("copy to ") { path = decodePath(String(line.dropFirst(8))) }
                else if line.hasPrefix("--- ") && !inHunk {
                    let value = decodePath(String(line.dropFirst(4)))
                    if value != "/dev/null" { oldPath = stripPrefix(value) }
                } else if line.hasPrefix("+++ ") && !inHunk {
                    let value = decodePath(String(line.dropFirst(4)))
                    if value != "/dev/null" { path = stripPrefix(value) }
                } else if line.hasPrefix("@@ ") { inHunk = true }
                else if inHunk && line.hasPrefix("+") { additions += 1 }
                else if inHunk && line.hasPrefix("-") { deletions += 1 }
                else if line.hasPrefix("Binary files ") || line == "GIT binary patch" { binary = true }
            }
            let patch = section.joined(separator: "\n")
            return CommitFilePatch(id: index, path: path, oldPath: change == .renamed || change == .copied ? oldPath : nil,
                                   change: change, additions: additions, deletions: deletions,
                                   isBinary: binary, patch: patch, diff: prepareDiff ? SplitDiff.parse(patch) : SplitDiff(rows: [], hasChanges: false))
        }
        let header = lines.prefix { !$0.hasPrefix("diff --") }
        return CommitPatch(files: files, fullDiff: prepareDiff ? SplitDiff.parse(text) : SplitDiff(rows: [], hasChanges: false),
                           isMerge: header.contains { $0.hasPrefix("Merge: ") })
    }

    private static func stripPrefix(_ path: String) -> String {
        path.hasPrefix("a/") || path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
    }

    private static func headerPaths(_ text: String) -> [String] {
        // Git leaves spaces unquoted, but quotes non-ASCII bytes and special characters.
        if !text.hasPrefix("\""), let divider = text.range(of: " b/", options: .backwards) {
            return [stripPrefix(String(text[..<divider.lowerBound])), String(text[divider.upperBound...])]
        }
        var tokens: [String] = []
        var token = ""
        var quoted = false
        var escaped = false
        for char in text {
            if char == " " && !quoted {
                if !token.isEmpty { tokens.append(stripPrefix(decodePath(token))); token = "" }
                continue
            }
            token.append(char)
            if escaped { escaped = false }
            else if char == "\\" && quoted { escaped = true }
            else if char == "\"" { quoted.toggle() }
        }
        if !token.isEmpty { tokens.append(stripPrefix(decodePath(token))) }
        return tokens
    }

    static func decodePath(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        let bytes = Array(path.dropFirst().dropLast().utf8)
        var decoded: [UInt8] = []
        var index = 0
        let escapes: [UInt8: UInt8] = [110: 10, 116: 9, 114: 13, 98: 8, 102: 12, 118: 11, 97: 7]
        while index < bytes.count {
            if bytes[index] == 92, index + 1 < bytes.count {
                index += 1
                if (48...55).contains(bytes[index]) {
                    var value = 0
                    var count = 0
                    while index < bytes.count && count < 3 && (48...55).contains(bytes[index]) {
                        value = value * 8 + Int(bytes[index] - 48); index += 1; count += 1
                    }
                    decoded.append(UInt8(truncatingIfNeeded: value))
                    continue
                }
                decoded.append(escapes[bytes[index]] ?? bytes[index])
            } else { decoded.append(bytes[index]) }
            index += 1
        }
        return String(decoding: decoded, as: UTF8.self)
    }
}
