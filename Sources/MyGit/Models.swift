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

struct ChangedFile: Identifiable, Hashable {
    var id: String { repositoryID.uuidString + ":" + path }
    let repositoryID: UUID
    let path: String
    let indexStatus: Character
    let worktreeStatus: Character
    let isUntracked: Bool

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
    let author: String
    let date: Date
    let subject: String
}

struct RepositorySnapshot: Identifiable {
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
