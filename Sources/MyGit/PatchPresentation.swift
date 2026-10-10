import Foundation

extension CommitFilePatch {
    private var metadata: [String] {
        Array(patch.components(separatedBy: "\n").prefix { !$0.hasPrefix("@@ ") })
    }

    var modeChangeDescription: String? {
        guard let old = metadata.first(where: { $0.hasPrefix("old mode ") }),
              let new = metadata.first(where: { $0.hasPrefix("new mode ") }) else { return nil }
        let before = String(old.dropFirst(9)), after = String(new.dropFirst(9))
        if before == "100644", after == "100755" { return "文件已增加可执行权限" }
        if before == "100755", after == "100644" { return "文件已移除可执行权限" }
        return AppLocalization.text("文件类型或权限已改变：%@ → %@", before, after)
    }

    var summaryTitle: String? {
        if isPureRename { return "文件已移动或重命名，内容未变" }
        if let binarySummaryTitle { return binarySummaryTitle }
        let lines = patch.components(separatedBy: "\n").filter { !$0.isEmpty }
        let modes = metadata.filter { $0.hasPrefix("index ") || $0.contains(" mode ") }
        if modes.contains(where: { $0.hasSuffix("160000") }) {
            let content = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") || $0.hasPrefix("-") && !$0.hasPrefix("---") }
            if !content.isEmpty && content.allSatisfy({ $0.dropFirst().hasPrefix("Subproject commit ") }) {
                switch change {
                case .added: return "新增子模块"
                case .deleted: return "子模块已删除"
                default: return "子模块版本已更新"
                }
            }
        }
        if modes.contains(where: { $0.hasSuffix("120000") }),
           !modes.contains(where: { $0.hasSuffix("100644") || $0.hasSuffix("100755") }) {
            switch change {
            case .added: return "新增符号链接"
            case .deleted: return "符号链接已删除"
            default: return "链接目标已修改"
            }
        }
        // Only summarize known metadata-only patches; never infer emptiness from line counts.
        let metadataOnly = lines.allSatisfy {
            $0.hasPrefix("diff --git ") || $0.hasPrefix("index ") || $0.hasPrefix("new file mode ")
                || $0.hasPrefix("deleted file mode ") || $0.hasPrefix("old mode ") || $0.hasPrefix("new mode ")
        }
        if metadataOnly {
            if change == .added { return "新增空文件" }
            if change == .deleted { return "空文件已删除" }
            if modeChangeDescription != nil { return "文件权限或类型已改变，内容未变" }
        }
        return nil
    }

    var summaryVersions: [(String, String)] {
        guard summaryTitle != nil else { return [] }
        let submodule = metadata.contains { $0.hasSuffix("160000") }
        let link = metadata.contains { $0.hasSuffix("120000") }
        guard submodule || link else { return [] }
        return patch.components(separatedBy: "\n").compactMap { line in
            guard (line.hasPrefix("+") && !line.hasPrefix("+++")) || (line.hasPrefix("-") && !line.hasPrefix("---")) else { return nil }
            var value = String(line.dropFirst())
            if submodule { value = String(value.dropFirst("Subproject commit ".count)) }
            return (line.hasPrefix("-") ? (submodule ? "原提交" : "原目标") : (submodule ? "新提交" : "新目标"), value)
        }
    }
}

enum PatchPresentation {
    static func readableText(_ text: String) -> String {
        text.components(separatedBy: "\n").map {
            $0 == "\\ No newline at end of file" ? AppLocalization.text("文件末尾没有换行符") : $0
        }.joined(separator: "\n")
    }
}
