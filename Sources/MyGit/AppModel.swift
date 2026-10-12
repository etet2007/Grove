import Foundation
import SwiftUI
import Combine

private struct WorktreeScan {
    let repository: Repository
    let worktrees: [Worktree]
    let error: String?
}

private struct GroupCacheKey: Hashable {
    let projectID: UUID
    let repositories: [Repository]
    let group: WorktreeGroup
    let commitLimits: [Int]
}

private struct GroupCacheEntry {
    let snapshots: [RepositorySnapshot]
    let commits: [Commit]
    var lastUsed: Date
}

private struct HistoryCacheKey: Hashable {
    let repositoryID: UUID
    let path: String
    let head: String
    let limit: Int
}

private struct MergeRequestCacheKey: Hashable {
    let path: String
    let branch: String
}

private struct MergeRequestCacheEntry {
    let url: URL?
}

@MainActor final class DetailState: ObservableObject {
    @Published var selectedFile: ChangedFile?
    @Published var selectedCommit: Commit?
    @Published var diffMode: DiffMode = .unstaged
    @Published var detail = ""
    @Published var splitDiff = SplitDiff(rows: [], hasChanges: false)
    @Published var commitPatch: CommitPatch?
    @Published var imagePreview: ImageDiffPreview?
    var generation = 0
    var task: Task<Void, Never>?
    var readSession: GitReadSession?

    func cancelRead() {
        task?.cancel()
        readSession?.cancel()
        task = nil
        readSession = nil
    }

    func clear() {
        cancelRead()
        generation += 1
        selectedFile = nil; selectedCommit = nil; detail = ""
        commitPatch = nil; imagePreview = nil
        splitDiff = SplitDiff(rows: [], hasChanges: false)
    }
}

@MainActor final class CommitBrowserScope: Identifiable {
    let id = UUID()
    let repositoryID: UUID?
    let detail = DetailState()

    init(repositoryID: UUID?) { self.repositoryID = repositoryID }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedWorktreeGroupID: UUID?
    @Published private(set) var snapshots: [RepositorySnapshot] = []
    @Published private(set) var commits: [Commit] = []
    private let changesState = DetailState()
    @Published private(set) var commitScopes = [CommitBrowserScope(repositoryID: nil)]
    @Published private(set) var commitRepositoryID: UUID?
    private var commitScopeInitialized = false
    private var rememberedCommitRepositories: [UUID: UUID?] = [:]
    var currentCommitScope: CommitBrowserScope {
        commitScopes.first { $0.repositoryID == commitRepositoryID }!
    }
    var detailStates: [DetailState] { [changesState, currentCommitScope.detail] }
    private var allDetailStates: [DetailState] { [changesState] + commitScopes.map(\.detail) }
    var browsingRepositoryID: UUID? { activeTab == 1 ? commitRepositoryID : focusedRepositoryID }
    var visibleCommits: [Commit] { commits.filter { commitRepositoryID == nil || $0.repositoryID == commitRepositoryID } }

    func selectBrowsingRepository(_ id: UUID?) {
        if activeTab == 1 { selectCommitRepository(id) }
        else {
            if focusedRepositoryID != id { changesState.clear() }
            focusedRepositoryID = id
        }
    }

    func selectCommitRepository(_ id: UUID?) {
        guard id == nil || selectedProject?.repositories.contains(where: { $0.id == id }) == true else { return }
        if !commitScopes.contains(where: { $0.repositoryID == id }) {
            commitScopes.append(CommitBrowserScope(repositoryID: id))
            observeDetails()
        }
        commitRepositoryID = id
        commitScopeInitialized = true
        if let projectID = selectedProjectID { rememberedCommitRepositories[projectID] = .some(id) }
    }

    private func reconcileCommitRepository() {
        let repositoryIDs = Set(selectedProject?.repositories.map(\.id) ?? [])
        let removed = commitScopes.filter { $0.repositoryID.map { !repositoryIDs.contains($0) } ?? false }
        if !removed.isEmpty {
            removed.forEach { $0.detail.clear() }
            // Select a surviving scope before publishing removal of the active one.
            if removed.contains(where: { $0.repositoryID == commitRepositoryID }) { commitRepositoryID = nil }
            commitScopes.removeAll { $0.repositoryID.map { !repositoryIDs.contains($0) } ?? false }
            commitScopeInitialized = false
            observeDetails()
        }
        if !commitScopeInitialized || (commitRepositoryID != nil && !snapshots.contains(where: { $0.repository.id == commitRepositoryID && $0.selected != nil })) {
            let remembered = selectedProjectID.flatMap { rememberedCommitRepositories[$0] }
            if let remembered, remembered == nil || snapshots.contains(where: { $0.repository.id == remembered && $0.selected != nil }) {
                selectCommitRepository(remembered)
            } else if let first = snapshots.first(where: { $0.selected != nil }) {
                selectCommitRepository(first.repository.id)
            }
        }
    }

    private func observeDetails() {
        detailObservers = allDetailStates.map { state in
            state.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    private var detailState: DetailState { detailStates[activeTab] }
    var selectedFile: ChangedFile? {
        get { detailState.selectedFile }
        set { detailState.selectedFile = newValue }
    }
    var selectedCommit: Commit? {
        get { detailState.selectedCommit }
        set { detailState.selectedCommit = newValue }
    }
    var diffMode: DiffMode {
        get { detailState.diffMode }
        set { detailState.diffMode = newValue }
    }
    var detail: String { detailState.detail }
    private var detailObservers: [AnyCancellable] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSwitchingBranch = false
    @Published private(set) var isDiscarding = false
    @Published var notice: String?
    @Published var error: String?
    @Published var activeTab = 0 {
        didSet {
            if activeTab == 0 && changesDetailNeedsRefresh {
                changesDetailNeedsRefresh = false
                loadDetail(showLoading: false, tab: 0)
            }
        }
    }
    @Published var showQuickSwitch = false
    @Published var focusedRepositoryID: UUID?

    private(set) var completedRefreshCount = 0
    private(set) var lastRefreshCommandCounts: [String: Int] = [:]
    private var mergeRequestCache: [MergeRequestCacheKey: MergeRequestCacheEntry] = [:]
    private var refreshTask: Task<Void, Never>?
    private var refreshSession: GitReadSession?
    private var refreshGeneration = 0
    private var repositoryCommitLimits: [UUID: Int] = [:]
    // Memory only: retain recent views without persisting repository contents.
    private var groupCache: [GroupCacheKey: GroupCacheEntry] = [:]
    private var historyCache: [HistoryCacheKey: [Commit]] = [:]

    private var currentCacheKey: GroupCacheKey? {
        guard let project = selectedProject, let group = selectedGroup else { return nil }
        return GroupCacheKey(projectID: project.id, repositories: project.repositories,
                             group: group, commitLimits: project.repositories.map { repositoryCommitLimits[$0.id] ?? 30 })
    }

    private func restoreCachedView() {
        changesDetailNeedsRefresh = false
        allDetailStates.forEach { $0.clear() }
        commitScopes = [CommitBrowserScope(repositoryID: nil)]
        commitRepositoryID = nil
        commitScopeInitialized = false
        observeDetails()
        if let key = currentCacheKey, var entry = groupCache[key] {
            entry.lastUsed = Date()
            groupCache[key] = entry
            snapshots = entry.snapshots
            commits = entry.commits
        } else {
            snapshots = []; commits = []
        }
        reconcileCommitRepository()
    }

    private func cacheCurrentView() {
        guard let key = currentCacheKey else { return }
        groupCache[key] = GroupCacheEntry(snapshots: snapshots, commits: commits, lastUsed: Date())
        if groupCache.count > 12,
           let oldest = groupCache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            groupCache.removeValue(forKey: oldest)
        }
    }
    var automaticRefreshEnabled = true
    private var changesDetailNeedsRefresh = false
    private let changeMonitor = RepositoryChangeMonitor()
    private var debounceTask: Task<Void, Never>?
    private var pendingPaths: Set<String> = []
    private var refreshRoots: [String] = []
    private var lastFullRefresh = Date.distantPast
    private let configURL: URL

    init(configURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.configURL = configURL ?? support.appendingPathComponent("MyGit", isDirectory: true).appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: self.configURL), let config = try? JSONDecoder().decode(Configuration.self, from: data) {
            projects = config.projects
            selectedProjectID = projects.first(where: { $0.id == config.selectedProjectID })?.id ?? projects.first?.id
            selectedWorktreeGroupID = selectedProject?.worktreeGroups.first(where: { $0.id == config.selectedWorktreeGroupID })?.id
                ?? selectedProject?.worktreeGroups.first?.id
        }
        observeDetails()
        changeMonitor.onChange = { [weak self] paths in self?.repositoryPathsChanged(paths) }
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
        } catch { self.error = AppLocalization.text("无法保存配置：%@", error.localizedDescription) }
    }

    func addProject(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var project = Project(name: name)
        project.worktreeGroups = [WorktreeGroup(name: "主目录", branch: nil, isPrimary: true)]
        projects.append(project)
        selectedProjectID = project.id
        selectedWorktreeGroupID = project.worktreeGroups[0].id
        focusedRepositoryID = nil
        restoreCachedView()
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
            } catch { self.error = AppLocalization.text("无法添加 %@：%@", path, error.localizedDescription) }
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
            error = AppLocalization.text("请先移动或移除这个仓库组中的仓库。")
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
        focusedRepositoryID = nil
        restoreCachedView()
        save(); refresh()
    }

    func removeWorktreeGroup(_ id: UUID) {
        guard let index = projectIndex,
              let group = projects[index].worktreeGroups.first(where: { $0.id == id }), !group.isPrimary else { return }
        if let branch = group.branch, !projects[index].hiddenBranches.contains(branch) {
            projects[index].hiddenBranches.append(branch)
        }
        projects[index].worktreeGroups.removeAll { $0.id == id }
        if selectedWorktreeGroupID == id {
            selectedWorktreeGroupID = projects[index].worktreeGroups.first?.id
            focusedRepositoryID = nil
            restoreCachedView()
        }
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
        restoreCachedView()
        focusedRepositoryID = nil
        save()
        refresh(useCachedHistory: true)
    }

    func selectWorktreeGroup(_ id: UUID) {
        selectedWorktreeGroupID = id
        restoreCachedView()
        focusedRepositoryID = nil
        save()
        refresh(useCachedHistory: true)
    }

    func selectWorktree(_ path: String?, for repositoryID: UUID) {
        guard let index = projectIndex,
              let groupIndex = projects[index].worktreeGroups.firstIndex(where: { $0.id == selectedWorktreeGroupID }) else { return }
        projects[index].worktreeGroups[groupIndex].selections[repositoryID] = path
        restoreCachedView()
        save(); refresh(useCachedHistory: true)
    }

    func switchBranch(_ branch: String, for repositoryID: UUID, checkoutPath: String) async {
        guard !isSwitchingBranch, !isDiscarding,
              let projectID = selectedProjectID, let groupID = selectedWorktreeGroupID,
              snapshots.contains(where: { $0.repository.id == repositoryID && $0.selected?.path == checkoutPath }) else { return }
        isSwitchingBranch = true
        refreshTask?.cancel()
        refreshSession?.cancel()
        refreshGeneration += 1
        isRefreshing = false
        allDetailStates.forEach { $0.clear() }
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            do { try GitClient.switchBranch(branch, in: checkoutPath); return nil }
            catch { return error.localizedDescription }
        }.value
        if let failure {
            error = AppLocalization.text("切换分支失败：%@", failure)
        } else if let index = projects.firstIndex(where: { $0.id == projectID }),
                  let groupIndex = projects[index].worktreeGroups.firstIndex(where: { $0.id == groupID }) {
            // Keep browsing the checkout the user changed, even if its branch
            // no longer matches the group's automatic branch selection.
            projects[index].worktreeGroups[groupIndex].selections[repositoryID] = checkoutPath
            if projects[index].worktreeGroups[groupIndex].isTransient {
                projects[index].worktreeGroups[groupIndex].isTransient = false
                projects[index].worktreeGroups[groupIndex].name = branch
                projects[index].worktreeGroups[groupIndex].branch = branch
            }
            save()
        }
        groupCache.removeAll()
        historyCache.removeAll()
        mergeRequestCache.removeAll()
        isSwitchingBranch = false
        refresh()
    }

    func selectFile(_ file: ChangedFile) {
        selectedFile = file
        selectedCommit = nil
        diffMode = file.hasUnstaged ? .unstaged : .staged
        loadDetail()
    }

    func discard(_ request: DiffDiscardRequest) async {
        guard !isDiscarding, !isSwitchingBranch else { return }
        isDiscarding = true
        refreshTask?.cancel()
        refreshSession?.cancel()
        refreshGeneration += 1
        isRefreshing = false
        allDetailStates.forEach { $0.cancelRead(); $0.generation += 1 }
        let failure = await Task.detached(priority: .userInitiated) { () -> String? in
            do { try DiffDiscard.apply(request); return nil }
            catch { return error.localizedDescription }
        }.value
        if let failure { error = AppLocalization.text("丢弃修改失败：%@", failure) }
        groupCache.removeAll()
        isDiscarding = false
        refresh()
    }

    func selectCommit(_ commit: Commit) {
        selectedCommit = commit
        selectedFile = nil
        detailState.imagePreview = nil
        loadDetail()
    }

    func loadMoreCommits() {
        let ids = commitRepositoryID.map { [$0] } ?? (selectedProject?.repositories.map(\.id) ?? [])
        for id in ids { repositoryCommitLimits[id] = (repositoryCommitLimits[id] ?? 30) + 30 }
        refresh(useCachedHistory: true)
    }

    private func repositoryPathsChanged(_ paths: [String]) {
        // Coalesce build/save bursts to a few checkout/metadata roots. FSEvents
        // already supplies real paths, so do no per-file disk IO on the UI thread.
        let affected = refreshRoots.filter { root in
            paths.contains { pathIsInside($0, root: root) || pathIsInside(root, root: $0) }
        }
        guard !affected.isEmpty else { return }
        pendingPaths.formUnion(affected)
        if affected.contains(where: { root in snapshots.contains { gitMetadataRoot(in: $0.repository.path) == root } }) {
            mergeRequestCache.removeAll()
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.automaticRefresh()
        }
    }

    func automaticRefresh() {
        guard automaticRefreshEnabled, !isRefreshing else { return }
        if Date().timeIntervalSince(lastFullRefresh) >= 30 {
            mergeRequestCache.removeAll()
            pendingPaths.removeAll()
            refresh(useCachedHistory: true)
        } else if !pendingPaths.isEmpty {
            let paths = pendingPaths
            pendingPaths.removeAll()
            if snapshots.contains(where: { snapshot in
                let metadata = gitMetadataRoot(in: snapshot.repository.path)
                return paths.contains { pathIsInside($0, root: metadata) }
            }) { mergeRequestCache.removeAll() }
            refresh(useCachedHistory: true, changedPaths: paths)
        }
    }

    func refresh(useCachedHistory: Bool = false, changedPaths: Set<String>? = nil) {
        guard !isSwitchingBranch, !isDiscarding else { return }
        let changedPaths = changedPaths.map { Set($0.map { canonicalFilesystemPath($0) }) }
        if changedPaths == nil {
            lastFullRefresh = Date()
            pendingPaths.removeAll()
        }
        refreshTask?.cancel()
        refreshSession?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        guard let project = selectedProject else {
            snapshots = []; commits = []; isRefreshing = false
            return
        }
        isRefreshing = true
        let projectID = project.id
        let session = GitReadSession()
        refreshSession = session
        refreshTask = Task.detached(priority: .utility) {
            let scans = await GitClient.$readSession.withValue(session) {
                await boundedConcurrentMap(project.repositories) { repository -> WorktreeScan in
                    do { return WorktreeScan(repository: repository, worktrees: try GitClient.worktrees(in: repository.path), error: nil) }
                    catch { return WorktreeScan(repository: repository, worktrees: [], error: error.localizedDescription) }
                }
            }
            await MainActor.run {
                guard self.refreshGeneration == generation, self.selectedProjectID == projectID else { return }
                self.apply(scans: scans, generation: generation, useCachedHistory: useCachedHistory, session: session, changedPaths: changedPaths)
            }
        }
    }

    private func apply(scans: [WorktreeScan], generation: Int, useCachedHistory: Bool, session: GitReadSession, changedPaths: Set<String>?) {
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
                    ?? WorktreeGroup(name: AppLocalization.text("Detached HEAD · %@ · %@", scan.repository.name, String(worktree.head.prefix(7))), branch: nil)
                group.isTransient = true
                group.selections[scan.repository.id] = worktree.path
                projects[index].worktreeGroups.append(group)
            }
        }
        if !projects[index].worktreeGroups.contains(where: { $0.id == selectedWorktreeGroupID }) {
            selectedWorktreeGroupID = projects[index].worktreeGroups.first?.id
            if !oldGroups.isEmpty { notice = AppLocalization.text("原工作树组已不可用，已切换到主目录。") }
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
                notice = AppLocalization.text("The selected worktree for %@ is unavailable. Fell back to the primary checkout.", scan.repository.name)
            }
            let selected = manual ?? WorktreeSelection.resolve(group: group, repositoryID: scan.repository.id, worktrees: scan.worktrees)
            let fallback = !group.isPrimary && selected?.isPrimary == true
            selections.append((scan.repository, scan.worktrees, selected, fallback, scan.error))
        }
        if projects[index] != originalProject { save() }
        refreshRoots = selections.compactMap { $0.2?.path } + scans.map { gitMetadataRoot(in: $0.repository.path) }
        changeMonitor.watch(scans.flatMap { scan in
            [scan.repository.path, gitMetadataRoot(in: scan.repository.path)] + scan.worktrees.map(\.path)
        })
        let previousSnapshots = snapshots
        let pathsToRead = Set(selections.compactMap { repository, _, selected, _, _ -> String? in
            guard let selected else { return nil }
            guard let changedPaths else { return selected.path }
            let metadata = gitMetadataRoot(in: repository.path)
            return changedPaths.contains { pathIsInside($0, root: selected.path) || pathIsInside($0, root: metadata) }
                || !previousSnapshots.contains(where: { $0.repository.id == repository.id && $0.selected == selected })
                ? selected.path : nil
        })
        let limits = repositoryCommitLimits
        let cachedHistory = useCachedHistory ? historyCache : [:]
        let cachedMergeRequests = useCachedHistory ? mergeRequestCache : [:]
        refreshTask = Task.detached(priority: .utility) {
            let snapshots = await GitClient.$readSession.withValue(session) {
                await boundedConcurrentMap(selections) { selection -> RepositorySnapshot in
                    let (repository, worktrees, selected, fallback, scanError) = selection
                    guard let selected else {
                        return RepositorySnapshot(repository: repository, worktrees: worktrees, selected: nil,
                                                  isFallback: false, files: [], error: scanError ?? AppLocalization.text("没有有效的检出目录"),
                                                  mergeRequestURL: nil)
                    }
                    let mergeRequestURL = selected.branch.flatMap {
                        let key = MergeRequestCacheKey(path: selected.path, branch: $0)
                        if let cached = cachedMergeRequests[key] { return cached.url }
                        return GitClient.mergeRequestURL(in: selected.path, branch: $0)
                    }
                    if !pathsToRead.contains(selected.path),
                       let previous = previousSnapshots.first(where: { $0.repository.id == repository.id && $0.selected == selected }),
                       previous.error == nil {
                        return RepositorySnapshot(repository: repository, worktrees: worktrees, selected: selected,
                                                  isFallback: fallback, files: previous.files,
                                                  error: scanError, mergeRequestURL: mergeRequestURL)
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
            }
            // Publish changes before history finishes so the file list is usable sooner.
            await MainActor.run {
                guard self.refreshGeneration == generation, self.selectedProjectID == projectID else { return }
                if self.snapshots != snapshots { self.snapshots = snapshots }
                self.reconcileCommitRepository()
            }
            let histories = await GitClient.$readSession.withValue(session) {
                await boundedConcurrentMap(snapshots) { snapshot -> (HistoryCacheKey, [Commit])? in
                    guard let selected = snapshot.selected else { return nil }
                    let limit = limits[snapshot.repository.id] ?? 30
                    let key = HistoryCacheKey(repositoryID: snapshot.repository.id, path: selected.path,
                                              head: selected.head, limit: limit)
                    guard let history = cachedHistory[key]
                        ?? (try? GitClient.commits(in: selected.path, repositoryID: snapshot.repository.id, limit: limit, revision: selected.head)) else { return nil }
                    return (key, history)
                }
            }
            var commits = histories.compactMap { $0 }.flatMap { $0.1 }
            let loadedHistory = Dictionary(uniqueKeysWithValues: histories.compactMap { $0 })
            commits.sort { $0.date > $1.date }
            let sortedCommits = commits
            let newHistory = loadedHistory
            await MainActor.run {
                guard self.refreshGeneration == generation, self.selectedProjectID == projectID else { return }
                self.completedRefreshCount += 1
                self.lastRefreshCommandCounts = session.counts
                if self.mergeRequestCache.count > 128 { self.mergeRequestCache.removeAll() }
                for snapshot in snapshots {
                    if let selected = snapshot.selected, let branch = selected.branch {
                        self.mergeRequestCache[MergeRequestCacheKey(path: selected.path, branch: branch)] = MergeRequestCacheEntry(url: snapshot.mergeRequestURL)
                    }
                }
                if self.commits != sortedCommits { self.commits = sortedCommits }
                if self.historyCache.count + newHistory.count > 128 { self.historyCache.removeAll() }
                self.historyCache.merge(newHistory) { _, new in new }
                self.cacheCurrentView()
                self.isRefreshing = false
                let changes = self.detailStates[0]
                if let file = changes.selectedFile {
                    if let current = snapshots.flatMap(\.files).first(where: { $0.id == file.id }) {
                        if current != file { changes.selectedFile = current }
                        if snapshots.contains(where: { $0.repository.id == file.repositoryID && $0.selected.map { pathsToRead.contains($0.path) } == true }) {
                            if self.activeTab == 0 { self.loadDetail(showLoading: false, tab: 0) }
                            else { self.changesDetailNeedsRefresh = true }
                        }
                    } else { changes.clear() }
                }
            }
        }
    }

    func loadDetail(showLoading: Bool = true, tab: Int? = nil) {
        let state = detailStates[tab ?? activeTab]
        state.cancelRead()
        state.generation += 1
        let generation = state.generation
        let file = state.selectedFile
        let commit = state.selectedCommit
        let mode = state.diffMode
        let snapshot = snapshots.first { $0.repository.id == (file?.repositoryID ?? commit?.repositoryID) }
        guard let path = snapshot?.selected?.path else { state.clear(); return }
        if showLoading {
            state.detail = AppLocalization.text("正在读取…")
            state.imagePreview = nil
            state.commitPatch = nil
            state.splitDiff = SplitDiff(rows: [], hasChanges: false)
        }
        let previousDetail = state.detail
        let previousDiff = state.splitDiff
        let session = GitReadSession()
        state.readSession = session
        state.task = Task.detached(priority: .utility) {
            await GitClient.$readSession.withValue(session) {
                let output: String
                let preview = file.flatMap { GitClient.imagePreview(for: $0, in: path, mode: mode) }
                do {
                    if let file { output = try GitClient.diff(for: file, in: path, mode: mode) }
                    else if let commit { output = try GitClient.show(commit, in: path) }
                    else { output = "" }
                } catch { output = error.localizedDescription }
                guard !Task.isCancelled, !session.isCancelled else { return }
                let patch = commit != nil ? CommitPatch.parse(output) : nil
                let splitDiff = file != nil
                    ? (output == previousDetail ? previousDiff : SplitDiff.parse(output))
                    : SplitDiff(rows: [], hasChanges: false)
                await MainActor.run {
                    guard state.generation == generation else { return }
                    if state.detail != output {
                        state.detail = output
                        state.splitDiff = splitDiff
                    }
                    state.imagePreview = preview
                    state.commitPatch = patch
                }
            }
        }
    }

    private var projectIndex: Int? { projects.firstIndex { $0.id == selectedProjectID } }
}
