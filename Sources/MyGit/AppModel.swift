import Foundation
import SwiftUI

private struct WorktreeScan {
    let repository: Repository
    let worktrees: [Worktree]
    let error: String?
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedWorktreeGroupID: UUID?
    @Published private(set) var snapshots: [RepositorySnapshot] = []
    @Published private(set) var commits: [Commit] = []
    @Published var selectedFile: ChangedFile?
    @Published var selectedCommit: Commit?
    @Published var diffMode: DiffMode = .unstaged
    @Published private(set) var detail = ""
    @Published private(set) var imagePreview: ImageDiffPreview?
    @Published private(set) var isRefreshing = false
    @Published var notice: String?
    @Published var error: String?
    @Published var activeTab = 0
    @Published var showQuickSwitch = false
    @Published var focusedRepositoryID: UUID?

    private var refreshGeneration = 0
    private var detailGeneration = 0
    private var commitLimit = 30
    private let configURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        configURL = support.appendingPathComponent("MyGit", isDirectory: true).appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL), let config = try? JSONDecoder().decode(Configuration.self, from: data) {
            projects = config.projects
            selectedProjectID = projects.first(where: { $0.id == config.selectedProjectID })?.id ?? projects.first?.id
            selectedWorktreeGroupID = selectedProject?.worktreeGroups.first(where: { $0.id == config.selectedWorktreeGroupID })?.id
                ?? selectedProject?.worktreeGroups.first?.id
        }
        refresh()
    }

    var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }
    var selectedGroup: WorktreeGroup? { selectedProject?.worktreeGroups.first { $0.id == selectedWorktreeGroupID } }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Configuration(projects: projects, selectedProjectID: selectedProjectID,
                                             selectedWorktreeGroupID: selectedWorktreeGroupID)).write(to: configURL, options: .atomic)
        } catch { self.error = "无法保存配置：\(error.localizedDescription)" }
    }

    func addProject(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var project = Project(name: name)
        project.worktreeGroups = [WorktreeGroup(name: "主目录", branch: nil, isPrimary: true)]
        projects.append(project)
        selectedProjectID = project.id
        selectedWorktreeGroupID = project.worktreeGroups[0].id
        save(); refresh()
    }

    func addRepositoryGroup(name: String) {
        guard let index = projectIndex else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        projects[index].groups.append(RepositoryGroup(name: name))
        save()
    }

    func addRepositories(paths: [String], to groupID: UUID) {
        guard let index = projectIndex else { return }
        for path in paths {
            do {
                let canonical = try GitClient.canonicalRepository(at: path)
                guard !projects[index].repositories.contains(where: { $0.path == canonical }) else { continue }
                let name = URL(fileURLWithPath: canonical).lastPathComponent
                projects[index].repositories.append(Repository(name: name, path: canonical, groupID: groupID))
            } catch { self.error = "无法添加 \(path)：\(error.localizedDescription)" }
        }
        save(); refresh()
    }

    func moveRepository(_ id: UUID, to groupID: UUID) {
        guard let index = projectIndex,
              projects[index].groups.contains(where: { $0.id == groupID }),
              let repositoryIndex = projects[index].repositories.firstIndex(where: { $0.id == id }) else { return }
        projects[index].repositories[repositoryIndex].groupID = groupID
        save()
    }

    func removeRepositoryGroup(_ id: UUID) {
        guard let index = projectIndex else { return }
        guard !projects[index].repositories.contains(where: { $0.groupID == id }) else {
            error = "请先移动或移除这个仓库组中的仓库。"
            return
        }
        projects[index].groups.removeAll { $0.id == id }
        save()
    }

    func removeRepository(_ id: UUID) {
        guard let index = projectIndex else { return }
        projects[index].repositories.removeAll { $0.id == id }
        for groupIndex in projects[index].worktreeGroups.indices {
            projects[index].worktreeGroups[groupIndex].selections.removeValue(forKey: id)
        }
        save(); refresh()
    }

    func addWorktreeGroup(name: String) {
        guard let index = projectIndex else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = WorktreeGroup(name: name, branch: nil)
        projects[index].worktreeGroups.append(group)
        selectedWorktreeGroupID = group.id
        save(); refresh()
    }

    func removeWorktreeGroup(_ id: UUID) {
        guard let index = projectIndex,
              let group = projects[index].worktreeGroups.first(where: { $0.id == id }), !group.isPrimary else { return }
        if let branch = group.branch, !projects[index].hiddenBranches.contains(branch) {
            projects[index].hiddenBranches.append(branch)
        }
        projects[index].worktreeGroups.removeAll { $0.id == id }
        if selectedWorktreeGroupID == id { selectedWorktreeGroupID = projects[index].worktreeGroups.first?.id }
        save(); refresh()
    }

    func restoreBranch(_ branch: String) {
        guard let index = projectIndex else { return }
        projects[index].hiddenBranches.removeAll { $0 == branch }
        save(); refresh()
    }

    func selectProject(_ id: UUID) {
        selectedProjectID = id
        selectedWorktreeGroupID = selectedProject?.worktreeGroups.first?.id
        selectedFile = nil; selectedCommit = nil; detail = ""; imagePreview = nil
        focusedRepositoryID = nil
        save()
        refresh()
    }

    func selectWorktreeGroup(_ id: UUID) {
        selectedWorktreeGroupID = id
        selectedFile = nil; selectedCommit = nil; detail = ""; imagePreview = nil
        focusedRepositoryID = nil
        snapshots = []; commits = []
        save()
        refresh()
    }

    func selectWorktree(_ path: String?, for repositoryID: UUID) {
        guard let index = projectIndex,
              let groupIndex = projects[index].worktreeGroups.firstIndex(where: { $0.id == selectedWorktreeGroupID }) else { return }
        projects[index].worktreeGroups[groupIndex].selections[repositoryID] = path
        selectedFile = nil; selectedCommit = nil; detail = ""; imagePreview = nil
        snapshots = []; commits = []
        save(); refresh()
    }

    func selectFile(_ file: ChangedFile) {
        selectedFile = file
        selectedCommit = nil
        diffMode = file.hasUnstaged ? .unstaged : .staged
        loadDetail()
    }

    func selectCommit(_ commit: Commit) {
        selectedCommit = commit
        selectedFile = nil
        imagePreview = nil
        loadDetail()
    }

    func loadMoreCommits() {
        commitLimit += 30
        refresh()
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        guard let project = selectedProject else {
            snapshots = []; commits = []; isRefreshing = false
            return
        }
        isRefreshing = true
        let projectID = project.id
        Task.detached(priority: .utility) {
            let scans = project.repositories.map { repository -> WorktreeScan in
                do { return WorktreeScan(repository: repository, worktrees: try GitClient.worktrees(in: repository.path), error: nil) }
                catch { return WorktreeScan(repository: repository, worktrees: [], error: error.localizedDescription) }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation, self.selectedProjectID == projectID else { return }
                self.apply(scans: scans, generation: generation)
            }
        }
    }

    private func apply(scans: [WorktreeScan], generation: Int) {
        guard let index = projectIndex else { return }
        let projectID = projects[index].id
        let originalProject = projects[index]
        let branches = Set(scans.flatMap { $0.worktrees.filter { !$0.isPrimary }.compactMap(\.branch) })
            .subtracting(projects[index].hiddenBranches)
        let existing = Set(projects[index].worktreeGroups.compactMap(\.branch))
        for branch in branches.subtracting(existing).sorted() {
            projects[index].worktreeGroups.append(WorktreeGroup(name: branch, branch: branch))
        }
        let oldGroups = projects[index].worktreeGroups
        projects[index].worktreeGroups.removeAll { group in
            guard let branch = group.branch else { return false }
            return !branches.contains(branch) && group.selections.isEmpty
        }
        // Detached worktrees have no branch. Give each a temporary, selectable group.
        let existingDetached = projects[index].worktreeGroups.filter(\.isTransient)
        projects[index].worktreeGroups.removeAll { $0.isTransient }
        for scan in scans {
            for worktree in scan.worktrees where worktree.isDetached && !worktree.isPrimary {
                var group = existingDetached.first(where: { $0.selections[scan.repository.id] == worktree.path })
                    ?? WorktreeGroup(name: "分离 HEAD · \(scan.repository.name) · \(worktree.head.prefix(7))", branch: nil)
                group.isTransient = true
                group.selections[scan.repository.id] = worktree.path
                projects[index].worktreeGroups.append(group)
            }
        }
        if !projects[index].worktreeGroups.contains(where: { $0.id == selectedWorktreeGroupID }) {
            selectedWorktreeGroupID = projects[index].worktreeGroups.first?.id
            if !oldGroups.isEmpty { notice = "原工作树组已不可用，已切换到主目录。" }
        }
        guard let group = selectedGroup else { isRefreshing = false; return }
        var selections: [(Repository, [Worktree], Worktree?, Bool, String?)] = []
        for scan in scans {
            let requested = group.selections[scan.repository.id]
            let manual = requested.flatMap { path in scan.worktrees.first(where: { $0.path == path }) }
            if requested != nil && manual == nil {
                if let groupIndex = projects[index].worktreeGroups.firstIndex(where: { $0.id == group.id }) {
                    projects[index].worktreeGroups[groupIndex].selections.removeValue(forKey: scan.repository.id)
                }
                notice = "\(scan.repository.name) 的已选 worktree 不可用，已回退到主目录。"
            }
            let selected = manual ?? WorktreeSelection.resolve(group: group, repositoryID: scan.repository.id, worktrees: scan.worktrees)
            let fallback = !group.isPrimary && selected?.isPrimary == true
            selections.append((scan.repository, scan.worktrees, selected, fallback, scan.error))
        }
        if projects[index] != originalProject { save() }
        let limit = commitLimit
        Task.detached(priority: .utility) {
            let snapshots = selections.map { repository, worktrees, selected, fallback, scanError -> RepositorySnapshot in
                guard let selected else {
                    return RepositorySnapshot(repository: repository, worktrees: worktrees, selected: nil,
                                              isFallback: false, files: [], error: scanError ?? "没有有效的检出目录",
                                              mergeRequestURL: nil)
                }
                let mergeRequestURL = selected.branch.flatMap {
                    GitClient.mergeRequestURL(in: selected.path, branch: $0)
                }
                do {
                    return RepositorySnapshot(repository: repository, worktrees: worktrees, selected: selected,
                                              isFallback: fallback, files: try GitClient.changedFiles(in: selected.path, repositoryID: repository.id),
                                              error: scanError, mergeRequestURL: mergeRequestURL)
                } catch {
                    return RepositorySnapshot(repository: repository, worktrees: worktrees, selected: selected,
                                              isFallback: fallback, files: [], error: error.localizedDescription,
                                              mergeRequestURL: mergeRequestURL)
                }
            }
            var commits: [Commit] = []
            for snapshot in snapshots {
                guard let path = snapshot.selected?.path else { continue }
                commits += (try? GitClient.commits(in: path, repositoryID: snapshot.repository.id, limit: limit)) ?? []
            }
            commits.sort { $0.date > $1.date }
            let sortedCommits = commits
            await MainActor.run {
                guard self.refreshGeneration == generation, self.selectedProjectID == projectID else { return }
                self.snapshots = snapshots
                self.commits = sortedCommits
                self.isRefreshing = false
                if let file = self.selectedFile, !snapshots.contains(where: { $0.files.contains(file) }) {
                    self.selectedFile = nil; self.detail = ""; self.imagePreview = nil
                } else if self.selectedFile != nil { self.loadDetail(showLoading: false) }
            }
        }
    }

    func loadDetail(showLoading: Bool = true) {
        detailGeneration += 1
        let generation = detailGeneration
        let file = selectedFile
        let commit = selectedCommit
        let mode = diffMode
        let snapshot = snapshots.first { $0.repository.id == (file?.repositoryID ?? commit?.repositoryID) }
        guard let path = snapshot?.selected?.path else { detail = ""; imagePreview = nil; return }
        if showLoading { detail = "正在读取…"; imagePreview = nil }
        Task.detached(priority: .utility) {
            let output: String
            let preview = file.flatMap { GitClient.imagePreview(for: $0, in: path, mode: mode) }
            do {
                if let file { output = try GitClient.diff(for: file, in: path, mode: mode) }
                else if let commit { output = try GitClient.show(commit, in: path) }
                else { output = "" }
            } catch { output = error.localizedDescription }
            await MainActor.run {
                guard self.detailGeneration == generation else { return }
                if self.detail != output { self.detail = output }
                self.imagePreview = preview
            }
        }
    }

    private var projectIndex: Int? { projects.firstIndex { $0.id == selectedProjectID } }
}
