import SwiftUI

private enum WorkbenchStyle {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let sidebar = Color(red: 0.105, green: 0.105, blue: 0.11)
    static let surface = Color(red: 0.16, green: 0.16, blue: 0.165)
    static let raised = Color(red: 0.21, green: 0.21, blue: 0.22)
    static let border = Color(red: 0.30, green: 0.32, blue: 0.36)
    static let accent = Color(red: 0.68, green: 0.78, blue: 1)
    static let muted = Color(red: 0.70, green: 0.73, blue: 0.79)
}

private struct WorkbenchButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(emphasized ? WorkbenchStyle.accent : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(emphasized ? WorkbenchStyle.accent.opacity(configuration.isPressed ? 0.25 : 0.14)
                                  : WorkbenchStyle.surface.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(emphasized ? WorkbenchStyle.accent.opacity(0.32) : WorkbenchStyle.border.opacity(0.65)))
    }
}

private struct IconActionButton: View {
    let systemName: String
    let hint: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? Color.primary : WorkbenchStyle.muted)
                .frame(width: 28, height: 28)
                .background(isHovered ? WorkbenchStyle.raised : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(hint)
        .accessibilityLabel(hint)
    }
}

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
    @Environment(\.openURL) private var openURL
    @State private var nameAction: NameAction?
    @State private var nameInput = ""
    @State private var quickQuery = ""
    @State private var detailLayout: DetailLayout = .split
    @State private var resetDetailScrollOnLoad = false
    @State private var worktreeGroupsExpanded = true
    @State private var repositoriesExpanded = true
    @FocusState private var quickSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
                .toolbar {
                    ToolbarItem(placement: .navigation) { projectMenu }
                }
        } detail: {
            if model.selectedProject == nil {
                ContentUnavailableView("还没有工程", systemImage: "externaldrive", description: Text("创建工程，再添加本地 Git 仓库。"))
                    .toolbar { Button("新建工程") { present(.project) } }
            } else {
                mainArea
            }
        }
        .tint(WorkbenchStyle.accent)
        .background(WorkbenchStyle.background)
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
            if let project = model.selectedProject {
                sidebarHeader("工作树组", action: .worktreeGroup, isExpanded: $worktreeGroupsExpanded)
                if worktreeGroupsExpanded {
                    ForEach(project.worktreeGroups) { group in
                        Button { model.selectWorktreeGroup(group.id) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: group.isPrimary ? "house" : "point.topleft.down.to.point.bottomright.curvepath")
                                    .font(.system(size: 12))
                                Text(group.name).lineLimit(1)
                                Spacer(minLength: 0)
                                if model.selectedWorktreeGroupID == group.id {
                                    Circle().fill(WorkbenchStyle.accent).frame(width: 5, height: 5)
                                }
                            }
                            .font(.system(size: 12, weight: model.selectedWorktreeGroupID == group.id ? .semibold : .regular))
                            .foregroundStyle(model.selectedWorktreeGroupID == group.id ? WorkbenchStyle.accent : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(model.selectedWorktreeGroupID == group.id ? WorkbenchStyle.accent.opacity(0.15) : Color.clear)
                            .overlay(alignment: .leading) {
                                if model.selectedWorktreeGroupID == group.id {
                                    Rectangle().fill(WorkbenchStyle.accent).frame(width: 2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .contextMenu {
                            if !group.isPrimary {
                                Button("删除工作树组", role: .destructive) { model.removeWorktreeGroup(group.id) }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
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
                                IconActionButton(systemName: "folder.badge.plus", hint: "导入仓库到\(group.name)") {
                                    chooseRepositories(for: group.id)
                                }
                            }
                            .contextMenu {
                                Button("删除仓库组") { model.removeRepositoryGroup(group.id) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(WorkbenchStyle.sidebar)
    }

    private var projectMenu: some View {
        Menu {
            ForEach(model.projects) { project in
                Button {
                    model.selectProject(project.id)
                } label: {
                    if model.selectedProjectID == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            if !model.projects.isEmpty { Divider() }
            Button("新建工程…") { present(.project) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(WorkbenchStyle.accent)
                Text(model.selectedProject?.name ?? "选择工程")
                    .lineLimit(1)
                if let count = model.selectedProject?.repositories.count {
                    Text("\(count) 仓库")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WorkbenchStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WorkbenchStyle.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("切换工程")
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
            IconActionButton(systemName: "plus", hint: action.title) {
                present(action)
            }
        }
        .font(.caption.weight(.semibold))
        .listRowInsets(EdgeInsets(top: 8, leading: -11, bottom: 4, trailing: 1))
    }

    private func repositoryRow(_ repository: Repository) -> some View {
        let snapshot = model.snapshots.first { $0.repository.id == repository.id }
        return Menu {
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
            HStack(spacing: 8) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchStyle.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.name).lineLimit(1)
                    if let selected = snapshot?.selected {
                        Text(selected.branch ?? "分离 HEAD")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let count = snapshot?.files.count, count > 0 {
                    Text("\(count)")
                        .font(.caption2).foregroundStyle(WorkbenchStyle.muted)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .focusEffectDisabled()
        .contextMenu {
            if let project = model.selectedProject {
                Menu("移动到仓库组") {
                    ForEach(project.groups) { group in
                        Button(group.name) { model.moveRepository(repository.id, to: group.id) }
                    }
                }
            }
            Button("移除仓库", role: .destructive) { model.removeRepository(repository.id) }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 14))
                            .foregroundStyle(WorkbenchStyle.accent)
                        Text(model.selectedGroup?.name ?? "工作树组")
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text("\(model.snapshots.count) 个仓库 · \(model.snapshots.reduce(0) { $0 + $1.files.count }) 个修改文件")
                        .font(.system(size: 11)).foregroundStyle(WorkbenchStyle.muted)
                }
                Spacer()
                if model.focusedRepositoryID != nil {
                    Button("显示全部仓库") { model.focusedRepositoryID = nil }
                        .buttonStyle(WorkbenchButtonStyle())
                }
                Menu {
                    ForEach(model.snapshots.filter {
                        model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID
                    }) { snapshot in
                        if let url = snapshot.mergeRequestURL {
                            Button("\(snapshot.repository.name) · \(snapshot.selected?.branch ?? "")") {
                                openURL(url)
                            }
                        } else {
                            Button("\(snapshot.repository.name) · 无可用分支或远端") {}
                                .disabled(true)
                        }
                    }
                } label: {
                    Label("创建 MR", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WorkbenchStyle.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(WorkbenchStyle.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(WorkbenchStyle.accent.opacity(0.32)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.snapshots.isEmpty || !model.snapshots.contains {
                    (model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID)
                        && $0.mergeRequestURL != nil
                })
                .help("在浏览器中打开 GitLab 创建页面，使用当前检出的分支")
                if model.isRefreshing { ProgressView().controlSize(.small) }
                Button { model.showQuickSwitch = true } label: { Label("快速切换", systemImage: "magnifyingglass") }
                    .buttonStyle(WorkbenchButtonStyle())
                    .help("⌘K")
                IconActionButton(systemName: "arrow.clockwise", hint: "刷新") { model.refresh() }
            }
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(WorkbenchStyle.sidebar)
            Rectangle().fill(WorkbenchStyle.border.opacity(0.45)).frame(height: 1)
            HStack {
                HStack(spacing: 2) {
                    contentTab("未提交修改", icon: "doc.badge.ellipsis", count: model.snapshots.reduce(0) { $0 + $1.files.count }, index: 0)
                    contentTab("提交记录", icon: "clock.arrow.circlepath", count: nil, index: 1)
                }
                .padding(3)
                .background(WorkbenchStyle.raised)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(WorkbenchStyle.sidebar)
            HSplitView {
                if model.activeTab == 0 { changesList } else { commitsList }
                detailPane
            }
        }
        .background(WorkbenchStyle.background)
    }

    private func contentTab(_ title: String, icon: String, count: Int?, index: Int) -> some View {
        let selected = model.activeTab == index
        return Button { model.activeTab = index } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                    .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(selected ? WorkbenchStyle.accent.opacity(0.15) : WorkbenchStyle.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.primary : WorkbenchStyle.muted)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(selected ? WorkbenchStyle.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
        .scrollContentBackground(.hidden)
        .background(WorkbenchStyle.background)
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
        .scrollContentBackground(.hidden)
        .background(WorkbenchStyle.background)
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
            if detailLayout == .split, let preview = model.imagePreview {
                ImageDiffView(preview: preview, oldTitle: oldDiffTitle, newTitle: newDiffTitle)
                    .id(detailScrollIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detailLayout == .split && splitDiff.hasChanges {
                SplitDiffView(diff: splitDiff, oldTitle: oldDiffTitle, newTitle: newDiffTitle,
                              resetID: detailScrollIdentity)
                    .id(detailScrollIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rawDetail
            }
        }
        .frame(minWidth: 430)
        .background(WorkbenchStyle.background)
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
        panel.message = "选择要导入的本地 Git 仓库目录"
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

private struct ImageDiffView: View {
    let preview: ImageDiffPreview
    let oldTitle: String
    let newTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(changeLabel, systemImage: "photo.on.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                side(preview.old, title: oldTitle)
                side(preview.new, title: newTitle)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var changeLabel: String {
        switch (preview.old.byteCount != nil, preview.new.byteCount != nil) {
        case (true, false): "图片已删除"
        case (false, true): "新增图片"
        case (true, true): "图片已修改"
        case (false, false): "图片变更"
        }
    }

    private func side(_ value: ImageDiffSide, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let count = value.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack {
                if let data = value.data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                } else {
                    ContentUnavailableView(value.message ?? "此图片格式无法预览", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
