import Foundation

struct Repository: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var groupID: UUID
}

struct RepositoryGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
}

struct WorktreeGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var branch: String?
    var isPrimary = false
    var isTransient = false
    var selections: [UUID: String] = [:]
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var groups: [RepositoryGroup] = []
    var repositories: [Repository] = []
    var worktreeGroups: [WorktreeGroup] = []
    var hiddenBranches: [String] = []
}

struct Configuration: Codable {
    var projects: [Project] = []
    var selectedProjectID: UUID?
    var selectedWorktreeGroupID: UUID?
}

struct Worktree: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let branch: String?
    let head: String
    let isPrimary: Bool
    let isDetached: Bool
}

enum FileChangeKind: String {
    case added = "A", modified = "M", deleted = "D", renamed = "R", copied = "C", conflict = "!C"
    var title: String {
        switch self {
        case .added: "新增"
        case .modified: "修改"
        case .deleted: "删除"
        case .renamed: "重命名"
        case .copied: "复制"
        case .conflict: "冲突"
        }
    }
}

struct FileChangeStats: Hashable {
    let additions: Int
    let deletions: Int
    var isBinary = false
}

struct ChangedFile: Identifiable, Hashable {
    var id: String { repositoryID.uuidString + ":" + path }
    let repositoryID: UUID
    let path: String
    let indexStatus: Character
    let worktreeStatus: Character
    let isUntracked: Bool
    var stats: FileChangeStats? = nil

    var changeKind: FileChangeKind {
        let status = String(indexStatus) + String(worktreeStatus)
        if ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(status) { return .conflict }
        if indexStatus == "D" || worktreeStatus == "D" { return .deleted }
        if isUntracked || indexStatus == "A" || worktreeStatus == "A" { return .added }
        if indexStatus == "R" || worktreeStatus == "R" { return .renamed }
        if indexStatus == "C" || worktreeStatus == "C" { return .copied }
        return .modified
    }

    var hasStaged: Bool { indexStatus != " " && indexStatus != "?" }
    var hasUnstaged: Bool { worktreeStatus != " " || isUntracked }
    var statusLabel: String {
        if isUntracked { return "未跟踪" }
        if hasStaged && hasUnstaged { return "已暂存 · 未暂存" }
        if hasStaged { return "已暂存" }
        return "未暂存"
    }
}

struct Commit: Identifiable, Hashable {
    var id: String { repositoryID.uuidString + ":" + hash }
    let repositoryID: UUID
    let hash: String
    let committer: String
    let date: Date
    let subject: String

    var formattedDate: String { Self.dateFormatter.string(from: date) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

struct RepositorySnapshot: Identifiable, Equatable {
    var id: UUID { repository.id }
    let repository: Repository
    let worktrees: [Worktree]
    let selected: Worktree?
    let isFallback: Bool
    let files: [ChangedFile]
    let error: String?
    let mergeRequestURL: URL?
}

enum DiffMode: String, CaseIterable, Identifiable {
    case unstaged = "未暂存"
    case staged = "已暂存"
    case all = "全部修改"
    var id: String { rawValue }
}

enum WorktreeSelection {
    static func resolve(group: WorktreeGroup, repositoryID: UUID, worktrees: [Worktree]) -> Worktree? {
        let primary = worktrees.first(where: \.isPrimary)
        if let path = group.selections[repositoryID], let manual = worktrees.first(where: { $0.path == path }) {
            return manual
        }
        if group.isPrimary { return primary }
        if let branch = group.branch, let match = worktrees.first(where: { !$0.isPrimary && $0.branch == branch }) {
            return match
        }
        return primary
    }
}
