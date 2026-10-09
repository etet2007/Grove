import SwiftUI

struct MergeSourceCommit: Identifiable, Equatable {
    let hash: String
    let author: String
    let email: String
    let subject: String
    var id: String { hash }
    var identity: String { "\(author) <\(email)>" }
}

extension Array where Element == MergeSourceCommit {
    var authorSummary: String {
        let identities = Dictionary(grouping: self, by: \.author)
        return identities.keys.sorted().flatMap { name in
            let people = Set(identities[name, default: []].map(\.identity)).sorted()
            return people.count > 1 ? people : [name]
        }.joined(separator: "、")
    }
}

extension GitClient {
    /// Related file history reachable from the incoming parents but not the first parent.
    /// This is file-level evidence, not attribution of the final merge's individual lines.
    static func mergeSources(commit: String, file: CommitFilePatch, in checkout: String) throws -> [MergeSourceCommit] {
        let ancestry = try text(["rev-list", "--parents", "-n", "1", commit], in: checkout)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard ancestry.count > 2 else { return [] }
        let incoming = Array(ancestry.dropFirst(2))
        let paths = Array(Set([file.path, file.oldPath].compactMap { $0 })).sorted()
        let output = try text(["log", "--full-history", "--no-merges",
                               "--format=%H%x00%an%x00%ae%x00%s%x00", "--no-ext-diff"]
                              + incoming + ["^" + ancestry[1], "--"]
                              + paths.map { ":(literal)" + $0 }, in: checkout)
        let fields = output.components(separatedBy: "\0")
        return stride(from: 0, to: max(0, fields.count - 4), by: 4).compactMap { index in
            let hash = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else { return nil }
            return MergeSourceCommit(hash: hash, author: fields[index + 1], email: fields[index + 2], subject: fields[index + 3])
        }
    }
}

struct MergeFileSourcesView: View {
    let commits: [MergeSourceCommit]?
    let failed: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if failed {
                Text(AppLocalization.text("无法读取合入来源，本地历史可能不完整。"))
            } else if let commits {
                if commits.isEmpty {
                    Text(AppLocalization.text("未找到该文件的合入来源提交，可能包含合并时修改。"))
                } else {
                    Text(AppLocalization.text("合入相关作者：%@", commits.authorSummary))
                        .lineLimit(2).help(commits.map(\.identity).uniqued().joined(separator: "\n"))
                    DisclosureGroup(AppLocalization.text("来源提交（%ld）", commits.count), isExpanded: $expanded) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(commits) { commit in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(commit.hash.prefix(8)) · \(commit.author) · \(commit.subject)")
                                        Text(commit.identity).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        .frame(maxHeight: 120)
                        .padding(.top, 6)
                    }
                    Text(AppLocalization.text("按合入历史列出相关提交；不代表逐行作者或冲突解决者。"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(AppLocalization.text("正在读取合入来源…"))
            }
        }
        .appFont(size: 11)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
