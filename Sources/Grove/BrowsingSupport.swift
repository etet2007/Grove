import Foundation

/// Backup only validated configurations; never replace the last good copy with unreadable data.
struct ConfigurationStore {
    let url: URL
    var backupURL: URL { url.appendingPathExtension("backup") }

    func load() throws -> Configuration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
    }

    func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(Configuration.self, from: old)) != nil {
            try old.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try data.write(to: backupURL, options: .atomic)
        }
    }

    var canRecover: Bool { (try? JSONDecoder().decode(Configuration.self, from: Data(contentsOf: backupURL))) != nil }

    func recover(useBackup: Bool) throws -> Configuration {
        let configuration = useBackup
            ? try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: backupURL))
            : Configuration(projects: [], selectedProjectID: nil, selectedWorktreeGroupID: nil)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: url.appendingPathExtension("damaged-\(UUID().uuidString)"))
        }
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: url, options: .atomic)
        return configuration
    }
}

enum FileChangeFilter: String, CaseIterable, Identifiable {
    case all = "所有修改", staged = "已暂存", unstaged = "未暂存", added = "新增", modified = "修改", deleted = "删除", renamed = "重命名或复制", conflict = "冲突"
    var id: String { rawValue }
    func includes(_ file: ChangedFile) -> Bool {
        switch self {
        case .all: return true
        case .staged: return file.hasStaged
        case .unstaged: return file.hasUnstaged
        case .added: return file.changeKind == .added
        case .modified: return file.changeKind == .modified
        case .deleted: return file.changeKind == .deleted
        case .renamed: return file.changeKind == .renamed || file.changeKind == .copied
        case .conflict: return file.changeKind == .conflict
        }
    }
}

enum HistorySearchField: String, CaseIterable, Identifiable {
    case title = "提交标题", author = "提交者", hash = "提交哈希", path = "文件路径"
    var id: String { rawValue }
    func matches(_ commit: Commit, query: String) -> Bool {
        switch self {
        case .title: return commit.subject.localizedCaseInsensitiveContains(query)
        case .author: return commit.committer.localizedCaseInsensitiveContains(query)
        case .hash: return commit.hash.localizedCaseInsensitiveContains(query)
        case .path: return false // File paths require an explicit local-history query.
        }
    }
}

struct PreparedCommitHistory {
    let source: [Commit]
    let commits: [Commit]
    let graph: CommitGraph
    let rows: [String: CommitGraph.Row]
    init(_ commits: [Commit]) {
        source = commits
        self.commits = CommitGraph.topologicalOrder(commits)
        graph = CommitGraph(commits: self.commits)
        rows = Dictionary(uniqueKeysWithValues: graph.rows.map { ($0.commit.id, $0) })
    }
}
