import SwiftUI

private enum WorkbenchStyle {
    static let background = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let sidebar = Color(red: 0.094, green: 0.094, blue: 0.106)
    static let surface = Color(red: 0.149, green: 0.149, blue: 0.169)
    static let raised = Color(red: 0.165, green: 0.165, blue: 0.188)
    static let border = Color(red: 0.22, green: 0.22, blue: 0.245)
    static let accent = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let selection = Color(red: 0.008, green: 0.518, blue: 0.78)
    static let muted = Color(red: 0.63, green: 0.63, blue: 0.67)

    static func repositoryColor(_ name: String) -> Color {
        let palette: [Color] = [accent, .orange, .green, .purple, .pink, .yellow]
        let hash = name.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

private struct WorkbenchButtonStyle: ButtonStyle {
    var emphasized = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(emphasized ? WorkbenchStyle.selection.opacity(configuration.isPressed ? 0.75 : 1)
                                  : WorkbenchStyle.surface.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(emphasized ? WorkbenchStyle.accent.opacity(0.32) : WorkbenchStyle.border.opacity(0.65)))
    }
}

private struct MergeRequestRowStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HoverRow(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct HoverRow: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @State private var isHovered = false

        var body: some View {
            label
                .background(isPressed ? WorkbenchStyle.raised : (isHovered ? WorkbenchStyle.surface : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .onHover { isHovered = $0 }
        }
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

// Keep the complete custom label and use a visible, anchored picker for selection.
private struct WorkbenchMenu<Content: View, Label: View>: View {
    let title: String
    var arrowEdge: Edge = .top
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false
    @State private var isMenuOpen = false

    var body: some View {
        Button { isMenuOpen.toggle() } label: {
            label()
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(isMenuOpen ? 0.14 : (isHovered ? 0.06 : 0)))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isMenuOpen, arrowEdge: arrowEdge) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) { content() }
                    .buttonStyle(PickerChoiceStyle { isMenuOpen = false })
                    .font(.system(size: 12))
                    .padding(8)
            }
            .frame(width: 320)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 360)
            .background(WorkbenchStyle.sidebar)
            .preferredColorScheme(.dark)
        }
    }
}

private struct PickerChoiceStyle: PrimitiveButtonStyle {
    let dismiss: () -> Void

    func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        Button {
            dismiss()
            configuration.trigger()
        } label: {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(MergeRequestRowStyle())
    }
}

private struct HideToolbarTitle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
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

private struct WorkbenchTabButton: View {
    let title: String
    let icon: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

enum DetailLayout: String, CaseIterable, Identifiable {
    case split = "并排模式"
    case patch = "统一内联"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var nameAction: NameAction?
    @State private var nameInput = ""
    @State private var quickQuery = ""
    @State private var showMergeRequestPicker = false
    @State private var collapsedRepositoryGroups: Set<UUID> = []
    @FocusState private var quickSearchFocused: Bool

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
            if model.selectedProject == nil {
                ContentUnavailableView("还没有工程", systemImage: "externaldrive", description: Text("从标题栏创建工程，再添加本地 Git 仓库。"))
            } else {
                mainArea
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { HStack(spacing: 0) { projectMenu } }
            ToolbarItem(placement: .navigation) { HStack(spacing: 0) { currentWorktreeMenu } }
            ToolbarItem(placement: .principal) { viewTabs }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            } else {
                ToolbarItem(placement: .automatic) { Spacer() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showQuickSwitch = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("⌘K").font(.system(size: 11, design: .monospaced)).foregroundStyle(WorkbenchStyle.muted)
                    }
                }
                .buttonStyle(WorkbenchButtonStyle())
                .help("搜索工程、工作树组或仓库 (⌘K)")
                IconActionButton(systemName: "arrow.clockwise", hint: "刷新 (⌘R)") { model.refresh() }
                    .overlay {
                        if model.isRefreshing {
                            ProgressView().controlSize(.mini).padding(4).background(WorkbenchStyle.surface)
                                .allowsHitTesting(false)
                        }
                    }
                HStack(spacing: 0) { mergeRequestMenu }
            }
        }
        .modifier(HideToolbarTitle())
        .toolbarBackground(WorkbenchStyle.sidebar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let project = model.selectedProject {
                        VStack(spacing: 2) {
                            sidebarHeader("工作树组", action: .worktreeGroup)
                            ForEach(project.worktreeGroups) { group in
                                worktreeRow(group)
                            }
                            if !project.hiddenBranches.isEmpty {
                                Menu("恢复隐藏的分支组") {
                                    ForEach(project.hiddenBranches, id: \.self) { branch in
                                        Button(branch) { model.restoreBranch(branch) }
                                    }
                                }
                                .font(.system(size: 11))
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            sidebarHeader("关联仓库", action: .repositoryGroup)
                            ForEach(project.groups) { group in
                                repositoryGroupRow(group, in: project)
                            }
                        }
                    }
                }
                .padding(8)
            }
            HStack(spacing: 6) {
                Circle().fill(model.isRefreshing ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(model.isRefreshing ? "正在刷新本地状态" : "本地仓库 · 自动刷新")
                Spacer(minLength: 0)
                Text("只读")
            }
            .font(.system(size: 10))
            .foregroundStyle(WorkbenchStyle.muted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .overlay(alignment: .top) { Divider() }
        }
        .background(WorkbenchStyle.sidebar)
    }

    private func repositoryGroupRow(_ group: RepositoryGroup, in project: Project) -> some View {
        let repositories = project.repositories.filter { $0.groupID == group.id }
        let expanded = !collapsedRepositoryGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Button {
                    if expanded { collapsedRepositoryGroups.insert(group.id) }
                    else { collapsedRepositoryGroups.remove(group.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 16)
                        Text(group.name).lineLimit(1)
                        Text("(\(repositories.count))")
                            .font(.system(size: 10, design: .monospaced))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkbenchStyle.muted)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(expanded ? "收起" : "展开")仓库组 \(group.name)")
                IconActionButton(systemName: "folder.badge.plus", hint: "导入仓库到\(group.name)") {
                    chooseRepositories(for: group.id)
                }
            }
            .padding(.horizontal, 10)
            .contextMenu {
                Button("删除仓库组") { model.removeRepositoryGroup(group.id) }
            }
            if expanded {
                ForEach(repositories) { repository in
                    repositoryRow(repository)
                }
            }
        }
    }

    private func worktreeRow(_ group: WorktreeGroup) -> some View {
        let selected = model.selectedWorktreeGroupID == group.id
        return Button { model.selectWorktreeGroup(group.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: group.isPrimary ? "arrow.triangle.branch" : "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : WorkbenchStyle.muted)
                Text(group.name).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Text("\(model.snapshots.filter { !$0.isFallback }.count) 仓")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(selected ? WorkbenchStyle.selection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            if !group.isPrimary {
                Button("删除工作树组", role: .destructive) { model.removeWorktreeGroup(group.id) }
            }
        }
    }

    private var projectMenu: some View {
        WorkbenchMenu(title: model.selectedProject?.name ?? "选择工程") {
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
                Image(systemName: "square.3.layers.3d")
                    .foregroundStyle(WorkbenchStyle.accent)
                Text(model.selectedProject?.name ?? "选择工程")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                if let count = model.selectedProject?.repositories.count {
                    Text("\(count) 仓库")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WorkbenchStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WorkbenchStyle.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WorkbenchStyle.muted)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 9).frame(height: 26)
            .background(WorkbenchStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(WorkbenchStyle.border))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换工程")
    }

    private func sidebarHeader(_ title: String, action: NameAction) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Color(red: 0.84, green: 0.84, blue: 0.87))
            Spacer(minLength: 0)
            IconActionButton(systemName: "plus", hint: action.title) {
                present(action)
            }
        }
        .foregroundStyle(WorkbenchStyle.muted)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func repositoryRow(_ repository: Repository) -> some View {
        let snapshot = model.snapshots.first { $0.repository.id == repository.id }
        return WorkbenchMenu(title: repository.name, arrowEdge: .leading) {
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
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(WorkbenchStyle.repositoryColor(repository.name))
                    .frame(width: 6, height: 6)
                    .frame(width: 16, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.name).font(.system(size: 12, weight: .regular)).lineLimit(1)
                    if let selected = snapshot?.selected {
                        Text(selected.branch ?? "分离 HEAD")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkbenchStyle.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let count = snapshot?.files.count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkbenchStyle.accent)
                }
            }
            .padding(.leading, 26)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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

    private var currentWorktreeMenu: some View {
        WorkbenchMenu(title: model.selectedGroup?.name ?? "工作树组") {
            ForEach(model.selectedProject?.worktreeGroups ?? []) { group in
                Button(group.name) { model.selectWorktreeGroup(group.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(model.selectedGroup?.name ?? "工作树组")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(WorkbenchStyle.surface.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(WorkbenchStyle.border))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: 210)
        .disabled(model.selectedProject == nil)
        .help(model.selectedGroup?.name ?? "选择工作树组")
    }

    private var viewTabs: some View {
        HStack(spacing: 2) {
            contentTab("未提交修改", icon: "doc.badge.ellipsis", count: nil, index: 0)
            contentTab("提交记录", icon: "clock.arrow.circlepath", count: nil, index: 1)
        }
        .padding(2)
        .background(WorkbenchStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchStyle.border))
        .disabled(model.selectedProject == nil)
    }

    private var mergeRequestMenu: some View {
        Button { showMergeRequestPicker.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge")
                Text("创建 MR")
            }
        }
        .buttonStyle(WorkbenchButtonStyle(emphasized: true))
        .fixedSize()
        .disabled(!model.snapshots.contains {
            (model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID) && $0.mergeRequestURL != nil
        })
        .help("选择仓库，在浏览器中打开 GitLab 创建页面")
        .popover(isPresented: $showMergeRequestPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择仓库创建 MR")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                Divider()
                ForEach(model.snapshots.filter {
                    model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID
                }) { snapshot in
                    Button {
                        guard let url = snapshot.mergeRequestURL else { return }
                        showMergeRequestPicker = false
                        openURL(url) { accepted in
                            if !accepted { model.error = "无法打开 GitLab 创建页面，请检查默认浏览器设置。" }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(WorkbenchStyle.repositoryColor(snapshot.repository.name))
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.repository.name).font(.system(size: 12, weight: .medium))
                                Text(snapshot.mergeRequestURL == nil ? "无可用分支或 GitLab 远端" : snapshot.selected?.branch ?? "")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(WorkbenchStyle.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MergeRequestRowStyle())
                    .disabled(snapshot.mergeRequestURL == nil)
                }
            }
            .padding(10)
            .frame(width: 340)
            .background(WorkbenchStyle.sidebar)
            .preferredColorScheme(.dark)
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            HSplitView {
                if model.activeTab == 0 { changesList } else { commitsList }
                detailPane
            }
            HStack {
                Text("\(model.snapshots.count) 个仓库 · \(model.snapshots.reduce(0) { $0 + $1.files.count }) 个修改文件")
                Spacer()
                if model.focusedRepositoryID != nil {
                    Button("显示全部仓库") { model.focusedRepositoryID = nil }.buttonStyle(.plain)
                        .foregroundStyle(WorkbenchStyle.accent)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(WorkbenchStyle.muted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(WorkbenchStyle.sidebar)
            .overlay(alignment: .top) { Divider() }
        }
        .background(WorkbenchStyle.background)
    }

    private func contentTab(_ title: String, icon: String, count: Int?, index: Int) -> some View {
        WorkbenchTabButton(title: title, icon: icon, count: count, selected: model.activeTab == index) {
            model.activeTab = index
        }
    }

    private var changesList: some View {
        List {
            ForEach(model.snapshots.filter { model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID }) { snapshot in
                Section {
                    if let error = snapshot.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    } else if snapshot.files.isEmpty {
                        Text("无未提交修改").font(.system(size: 10)).foregroundStyle(WorkbenchStyle.muted)
                    } else {
                        ForEach(snapshot.files) { file in
                            Button { model.selectFile(file) } label: {
                                ChangedFileRow(file: file, selected: model.selectedFile?.id == file.id)
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        }
                    }
                } header: {
                    HStack {
                        Text(snapshot.repository.name).lineLimit(1)
                        if snapshot.isFallback { Text("共享主目录").foregroundStyle(.orange) }
                        if let selected = snapshot.selected {
                            Text(selected.branch ?? "分离 HEAD").foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        let conflicts = snapshot.files.filter { $0.changeKind == .conflict }.count
                        if conflicts > 0 {
                            Text("\(conflicts) 冲突").foregroundStyle(.red).fixedSize()
                        }
                        Text("\(snapshot.files.count) 变动").foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 340)
        .scrollContentBackground(.hidden)
        .background(WorkbenchStyle.background)
    }

    private var commitsList: some View {
        List {
            ForEach(model.commits.filter { model.focusedRepositoryID == nil || $0.repositoryID == model.focusedRepositoryID }) { commit in
                Button { model.selectCommit(commit) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(commit.subject).lineLimit(2)
                            .font(.system(size: 12, weight: model.selectedCommit == commit ? .semibold : .medium))
                        HStack {
                            Text(model.selectedProject?.repositories.first(where: { $0.id == commit.repositoryID })?.name ?? "仓库")
                            Text(commit.hash.prefix(7))
                            Text(commit.date, style: .relative)
                        }
                        .font(.system(size: 10)).foregroundStyle(WorkbenchStyle.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            Button("加载更早提交") { model.loadMoreCommits() }
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 280, idealWidth: 340)
        .scrollContentBackground(.hidden)
        .background(WorkbenchStyle.background)
    }

    private var detailPane: some View {
        ZStack {
            ForEach(0..<2) { tab in
                DetailPaneView(state: model.detailStates[tab], tab: tab)
                    .opacity(model.activeTab == tab ? 1 : 0)
                    .allowsHitTesting(model.activeTab == tab)
                    .accessibilityHidden(model.activeTab != tab)
            }
        }
        .frame(minWidth: 430)
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

// Keep both panes mounted so their file selection, layout and native scroll
// positions survive tab switches without reloading the selected diff.
private struct DetailPaneView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: DetailState
    let tab: Int
    @State private var detailLayout: DetailLayout = .split
    @State private var resetDetailScrollOnLoad = false

    var body: some View { detailPane }

    private var detailPane: some View {
        let splitDiff = state.selectedCommit == nil ? SplitDiff.parse(state.detail) : SplitDiff(rows: [], hasChanges: false)
        return VStack(spacing: 0) {
            if let file = state.selectedFile {
                Text(file.path).font(.headline).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 12)
                    .help(file.path)
            }
            HStack {
                if state.selectedFile != nil {
                    Picker("Diff", selection: $state.diffMode) {
                        ForEach(DiffMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: state.diffMode) { _, _ in model.loadDetail(tab: tab) }
                } else if let commit = state.selectedCommit {
                    Text(commit.subject).font(.headline).lineLimit(1)
                } else {
                    Text("选择文件或提交").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if state.selectedFile != nil || state.selectedCommit != nil {
                    HStack(spacing: 2) {
                        ForEach(DetailLayout.allCases) { layout in
                            WorkbenchTabButton(title: layout.rawValue,
                                               icon: layout == .split ? "rectangle.split.1x2" : "rectangle.split.2x1",
                                               selected: detailLayout == layout) {
                                detailLayout = layout
                            }
                        }
                    }
                    .padding(2)
                    .background(WorkbenchStyle.background)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchStyle.border))
                    .fixedSize()
                }
            }
            .padding(12)
            Divider()
            if let commit = state.selectedCommit, let patch = state.commitPatch, !patch.files.isEmpty {
                CommitDetailView(patch: patch, layout: detailLayout)
                    .id(commit.id)
            } else if detailLayout == .split, let preview = state.imagePreview {
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
                Text(state.detail.isEmpty ? "选择左侧项目查看详情。" : state.detail)
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
            .onChange(of: state.detail) { _, _ in
                guard resetDetailScrollOnLoad, state.detail != "正在读取…" else { return }
                proxy.scrollTo("diff-content", anchor: .topLeading)
                resetDetailScrollOnLoad = false
            }
        }
    }

    private var oldDiffTitle: String {
        if state.selectedCommit != nil { return "父提交" }
        if state.selectedFile?.isUntracked == true { return "空文件" }
        return state.diffMode == .unstaged ? "暂存区" : "HEAD"
    }

    private var newDiffTitle: String {
        if state.selectedCommit != nil { return "提交后" }
        return state.diffMode == .staged ? "暂存区" : "工作区"
    }

    private var detailScrollIdentity: String {
        if let file = state.selectedFile { return "file:\(file.id):\(state.diffMode.rawValue)" }
        if let commit = state.selectedCommit { return "commit:\(commit.id)" }
        return "empty"
    }

}

private struct ChangedFileRow: View {
    let file: ChangedFile
    let selected: Bool

    private var color: Color {
        switch file.changeKind {
        case .added: .green
        case .modified: .purple
        case .deleted: .red
        case .renamed, .copied: .cyan
        case .conflict: .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Text(file.changeKind.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 22, height: 20)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text((file.path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? WorkbenchStyle.accent : Color.primary)
                        .strikethrough(file.changeKind == .deleted)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if file.hasStaged && file.changeKind != .conflict {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .help(file.hasUnstaged ? "已暂存，另有未暂存修改" : "已暂存")
                    }
                    Group {
                        if let stats = file.stats {
                            if stats.isBinary {
                                Text("二进制").foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 5) {
                                    Text("+\(stats.additions)").foregroundStyle(.green)
                                    Text("−\(stats.deletions)").foregroundStyle(.red)
                                }
                                .help("已暂存和未暂存修改的增删行数合计")
                            }
                        } else { Text("—").foregroundStyle(.secondary).help("暂无行数统计") }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize()
                }
                Text((file.path as NSString).deletingLastPathComponent)
                    .font(.system(size: 9)).foregroundStyle(WorkbenchStyle.muted)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(height: 11, alignment: .leading)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? WorkbenchStyle.surface : Color.clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(WorkbenchStyle.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .help("\(file.changeKind.title) · \(file.path)")
    }
}
