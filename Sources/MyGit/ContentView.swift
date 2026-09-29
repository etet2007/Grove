import SwiftUI

private enum NameAction: String, Identifiable {
    case project, repositoryGroup, worktreeGroup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .project: "新建工程"
        case .repositoryGroup: "新建仓库组"
        case .worktreeGroup: "新建工作树组"
        }
    }
}

private enum DetailLayout: String, CaseIterable, Identifiable {
    case split = "并排"
    case patch = "原始"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var nameAction: NameAction?
    @State private var nameInput = ""
    @State private var quickQuery = ""
    @State private var detailLayout: DetailLayout = .split
    @State private var resetDetailScrollOnLoad = false
    @State private var projectsExpanded = true
    @State private var worktreeGroupsExpanded = true
    @State private var repositoriesExpanded = true
    @FocusState private var quickSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if model.selectedProject == nil {
                ContentUnavailableView("还没有工程", systemImage: "externaldrive", description: Text("创建工程，再添加本地 Git 仓库。"))
                    .toolbar { Button("新建工程") { present(.project) } }
            } else {
                mainArea
            }
        }
        .sheet(item: $nameAction) { action in
            NameSheet(title: action.title, name: $nameInput) { value in
                switch action {
                case .project: model.addProject(name: value)
                case .repositoryGroup: model.addRepositoryGroup(name: value)
                case .worktreeGroup: model.addWorktreeGroup(name: value)
                }
                nameAction = nil
            }
            .frame(width: 360)
            .padding()
        }
        .sheet(isPresented: $model.showQuickSwitch) {
            quickSwitch
                .frame(width: 480, height: 420)
                .padding()
        }
        .alert(model.error == nil ? "工作树已变化" : "无法完成操作",
               isPresented: Binding(get: { model.error != nil || model.notice != nil },
                                    set: { if !$0 { model.error = nil; model.notice = nil } })) {
            Button("好") { model.error = nil; model.notice = nil }
        } message: { Text(model.error ?? model.notice ?? "") }
        .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
            if !model.isRefreshing { model.refresh() }
        }
    }

    private var sidebar: some View {
        List {
            sidebarHeader("工程", action: .project, isExpanded: $projectsExpanded)
            if projectsExpanded {
                ForEach(model.projects) { project in
                    Button {
                        model.selectProject(project.id)
                    } label: {
                        Label(project.name, systemImage: "square.stack.3d.up")
                            .fontWeight(model.selectedProjectID == project.id ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let project = model.selectedProject {
                sidebarHeader("工作树组", action: .worktreeGroup, isExpanded: $worktreeGroupsExpanded)
                if worktreeGroupsExpanded {
                    ForEach(project.worktreeGroups) { group in
                        HStack {
                            Button { model.selectWorktreeGroup(group.id) } label: {
                                Label(group.name, systemImage: group.isPrimary ? "house" : "square.stack")
                                    .fontWeight(model.selectedWorktreeGroupID == group.id ? .semibold : .regular)
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                            if !group.isPrimary {
                                Button { model.removeWorktreeGroup(group.id) } label: {
                                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("移除工作树组")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if !project.hiddenBranches.isEmpty {
                        Menu("恢复隐藏的分支组") {
                            ForEach(project.hiddenBranches, id: \.self) { branch in
                                Button(branch) { model.restoreBranch(branch) }
                            }
                        }
                    }
                }
                sidebarHeader("仓库", action: .repositoryGroup, isExpanded: $repositoriesExpanded)
                if repositoriesExpanded {
                    ForEach(project.groups) { group in
                        DisclosureGroup {
                            ForEach(project.repositories.filter { $0.groupID == group.id }) { repository in
                                repositoryRow(repository)
                            }
                        } label: {
                            HStack {
                                Text(group.name)
                                Spacer(minLength: 0)
                                Button { chooseRepositories(for: group.id) } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("添加仓库到\(group.name)")
                                .accessibilityLabel("添加仓库到\(group.name)")
                            }
                        }
                        .contextMenu {
                            Button("删除仓库组") { model.removeRepositoryGroup(group.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarHeader(_ title: String, action: NameAction, isExpanded: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Button { isExpanded.wrappedValue.toggle() } label: {
                HStack {
                    Text(title)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isExpanded.wrappedValue ? "收起\(title)" : "展开\(title)")
            .accessibilityLabel(isExpanded.wrappedValue ? "收起\(title)" : "展开\(title)")
            Button { present(action) } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(action.title)
            .accessibilityLabel(action.title)
        }
        .font(.caption.weight(.semibold))
        .listRowInsets(EdgeInsets(top: 8, leading: -11, bottom: 4, trailing: 1))
    }

    private func repositoryRow(_ repository: Repository) -> some View {
        let snapshot = model.snapshots.first { $0.repository.id == repository.id }
        return HStack(spacing: 6) {
            Menu {
                Button("恢复自动匹配") { model.selectWorktree(nil, for: repository.id) }
                Divider()
                ForEach(snapshot?.worktrees ?? []) { worktree in
                    Button {
                        model.selectWorktree(worktree.path, for: repository.id)
                    } label: {
                        Text("\(worktree.branch ?? "分离 HEAD") · \(worktree.isPrimary ? "主目录" : URL(fileURLWithPath: worktree.path).lastPathComponent)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.name).lineLimit(1)
                        if let selected = snapshot?.selected {
                            Text(selected.branch ?? "分离 HEAD")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            if let count = snapshot?.files.count, count > 0 {
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
            }
            Button { model.removeRepository(repository.id) } label: {
                Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain).help("从工程中移除仓库")
        }
        .padding(.leading, 8)
        .contextMenu {
            if let project = model.selectedProject {
                Menu("移动到仓库组") {
                    ForEach(project.groups) { group in
                        Button(group.name) { model.moveRepository(repository.id, to: group.id) }
                    }
                }
            }
            Button("移除仓库") { model.removeRepository(repository.id) }
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedGroup?.name ?? "工作树组").font(.title2.bold())
                    Text("\(model.snapshots.count) 个仓库 · \(model.snapshots.reduce(0) { $0 + $1.files.count }) 个修改文件")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.focusedRepositoryID != nil {
                    Button("显示全部仓库") { model.focusedRepositoryID = nil }
                }
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button { model.showQuickSwitch = true } label: { Label("快速切换", systemImage: "magnifyingglass") }
                    .help("⌘K")
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新")
            }
            .padding(16)
            Divider()
            Picker("内容", selection: $model.activeTab) {
                Text("未提交修改").tag(0)
                Text("提交记录").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            .padding(.vertical, 10)
            HSplitView {
                if model.activeTab == 0 { changesList } else { commitsList }
                detailPane
            }
        }
    }

    private var changesList: some View {
        List {
            ForEach(model.snapshots.filter { model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID }) { snapshot in
                Section {
                    if let error = snapshot.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if snapshot.files.isEmpty {
                        Text("无未提交修改").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.files) { file in
                            Button { model.selectFile(file) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    Text(file.path).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(file.statusLabel).font(.caption2).foregroundStyle(.secondary)
                                }
                                .fontWeight(model.selectedFile == file ? .semibold : .regular)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text(snapshot.repository.name)
                        if snapshot.isFallback { Text("共享主目录").foregroundStyle(.orange) }
                        if let selected = snapshot.selected {
                            Text(selected.branch ?? "分离 HEAD").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 330, idealWidth: 430)
    }

    private var commitsList: some View {
        List {
            ForEach(model.commits.filter { model.focusedRepositoryID == nil || $0.repositoryID == model.focusedRepositoryID }) { commit in
                Button { model.selectCommit(commit) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.subject).lineLimit(2)
                            .fontWeight(model.selectedCommit == commit ? .semibold : .regular)
                        HStack {
                            Text(model.selectedProject?.repositories.first(where: { $0.id == commit.repositoryID })?.name ?? "仓库")
                            Text(commit.hash.prefix(7))
                            Text(commit.date, style: .relative)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            Button("加载更早提交") { model.loadMoreCommits() }
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 330, idealWidth: 430)
    }

    private var detailPane: some View {
        let splitDiff = SplitDiff.parse(model.detail)
        return VStack(spacing: 0) {
            HStack {
                if let file = model.selectedFile {
                    Text(file.path).font(.headline).lineLimit(1)
                    Spacer()
                    Picker("Diff", selection: $model.diffMode) {
                        ForEach(DiffMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: model.diffMode) { _, _ in model.loadDetail() }
                } else if let commit = model.selectedCommit {
                    Text(commit.subject).font(.headline).lineLimit(1)
                } else {
                    Text("选择文件或提交").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.selectedFile != nil || model.selectedCommit != nil {
                    Picker("视图", selection: $detailLayout) {
                        ForEach(DetailLayout.allCases) { layout in Text(layout.rawValue).tag(layout) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            .padding(12)
            Divider()
            if detailLayout == .split && splitDiff.hasChanges {
                SplitDiffView(diff: splitDiff, oldTitle: oldDiffTitle, newTitle: newDiffTitle,
                              resetID: detailScrollIdentity)
                    .id(detailScrollIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rawDetail
            }
        }
        .frame(minWidth: 430)
    }

    private var rawDetail: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                Text(model.detail.isEmpty ? "选择左侧项目查看详情。" : model.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
                    .id("diff-content")
            }
            .onAppear { proxy.scrollTo("diff-content", anchor: .topLeading) }
            .onChange(of: detailScrollIdentity) { _, _ in
                resetDetailScrollOnLoad = true
                proxy.scrollTo("diff-content", anchor: .topLeading)
            }
            .onChange(of: model.detail) { _, _ in
                guard resetDetailScrollOnLoad, model.detail != "正在读取…" else { return }
                proxy.scrollTo("diff-content", anchor: .topLeading)
                resetDetailScrollOnLoad = false
            }
        }
    }

    private var oldDiffTitle: String {
        if model.selectedCommit != nil { return "父提交" }
        if model.selectedFile?.isUntracked == true { return "空文件" }
        return model.diffMode == .unstaged ? "暂存区" : "HEAD"
    }

    private var newDiffTitle: String {
        if model.selectedCommit != nil { return "提交后" }
        return model.diffMode == .staged ? "暂存区" : "工作区"
    }

    private var detailScrollIdentity: String {
        if let file = model.selectedFile { return "file:\(file.id):\(model.diffMode.rawValue)" }
        if let commit = model.selectedCommit { return "commit:\(commit.id)" }
        return "empty"
    }

    private var quickSwitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速切换").font(.title2.bold())
            TextField("搜索工程、工作树组或仓库", text: $quickQuery)
                .textFieldStyle(.roundedBorder)
                .focused($quickSearchFocused)
                .onSubmit { chooseFirstQuickResult() }
            List {
                ForEach(model.projects) { project in
                    if quickQuery.isEmpty || project.name.localizedCaseInsensitiveContains(quickQuery) {
                        Button("工程 · \(project.name)") {
                            model.selectProject(project.id); model.showQuickSwitch = false
                        }
                    }
                    ForEach(project.worktreeGroups) { group in
                        if quickQuery.isEmpty || group.name.localizedCaseInsensitiveContains(quickQuery) || project.name.localizedCaseInsensitiveContains(quickQuery) {
                            Button("\(project.name) / \(group.name)") {
                                model.selectProject(project.id)
                                model.selectWorktreeGroup(group.id)
                                model.showQuickSwitch = false
                            }
                        }
                    }
                    ForEach(project.repositories) { repository in
                        if repository.name.localizedCaseInsensitiveContains(quickQuery) {
                            Button("仓库 · \(repository.name)") {
                                model.selectProject(project.id)
                                model.focusedRepositoryID = repository.id
                                model.showQuickSwitch = false
                            }
                        }
                    }
                }
            }
        }
        .onAppear { quickQuery = ""; quickSearchFocused = true }
    }

    private func present(_ action: NameAction) {
        nameInput = ""
        nameAction = action
    }

    private func chooseRepositories(for groupID: UUID) {
        let panel = NSOpenPanel()
        panel.message = "选择一个或多个本地 Git 仓库目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in model.addRepositories(paths: panel.urls.map(\.path), to: groupID) }
        }
    }

    private func chooseFirstQuickResult() {
        let query = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        for project in model.projects {
            if let group = project.worktreeGroups.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
                model.selectProject(project.id)
                model.selectWorktreeGroup(group.id)
                model.showQuickSwitch = false
                return
            }
        }
        for project in model.projects {
            if let repository = project.repositories.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
                model.selectProject(project.id)
                model.focusedRepositoryID = repository.id
                model.showQuickSwitch = false
                return
            }
            if project.name.localizedCaseInsensitiveContains(query) {
                model.selectProject(project.id)
                model.showQuickSwitch = false
                return
            }
        }
    }
}

private struct NameSheet: View {
    let title: String
    @Binding var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            TextField("名称", text: $name)
                .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onSave(name) } }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("创建") { onSave(name) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
