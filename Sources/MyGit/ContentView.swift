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
        .help(AppLocalization.text(hint))
        .accessibilityLabel(AppLocalization.text(hint))
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
        .accessibilityLabel(Text(LocalizedStringKey(title)))
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
        .overlay {
            if model.showQuickSwitch {
                ZStack {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { model.showQuickSwitch = false }

                    quickSwitch
                        .frame(width: 480, height: 420)
                        .padding()
                        .background(WorkbenchStyle.sidebar)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                        .onTapGesture { }
                }
                .zIndex(1)
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
                        Text(LocalizedStringKey(group.name)).lineLimit(1)
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
                .accessibilityLabel(AppLocalization.text(expanded ? "收起仓库组 %@" : "展开仓库组 %@", group.name))
                IconActionButton(systemName: "folder.badge.plus", hint: AppLocalization.text("导入仓库到%@", group.name)) {
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
                Text(LocalizedStringKey(group.name)).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Text(AppLocalization.text("%ld repos", model.snapshots.filter { !$0.isFallback }.count))
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
                    Text(AppLocalization.text("%ld repositories", count))
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
            Text(LocalizedStringKey(title))
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
                    Text(AppLocalization.text("%@ · %@", worktree.branch ?? AppLocalization.text("分离 HEAD"), worktree.isPrimary ? AppLocalization.text("主目录") : URL(fileURLWithPath: worktree.path).lastPathComponent))
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
                        Text(selected.branch ?? AppLocalization.text("分离 HEAD"))
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
                        Button(LocalizedStringKey(group.name)) { model.moveRepository(repository.id, to: group.id) }
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
                Button(LocalizedStringKey(group.name)) { model.selectWorktreeGroup(group.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(AppLocalization.text(model.selectedGroup?.name ?? "工作树组"))
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
                Text(AppLocalization.text("%ld repositories · %ld changed files", model.snapshots.count, model.snapshots.reduce(0) { $0 + $1.files.count }))
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
        let selected = model.activeTab == index
        return Button { model.activeTab = index } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                    .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                Text(AppLocalization.text(title))
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
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").foregroundStyle(WorkbenchStyle.repositoryColor(snapshot.repository.name))
                                    Text(file.path).lineLimit(1)
                                    Spacer(minLength: 0)
                    Text(LocalizedStringKey(file.statusLabel)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .font(.system(size: 12, weight: model.selectedFile == file ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text(snapshot.repository.name)
                        if snapshot.isFallback { Text("共享主目录").foregroundStyle(.orange) }
                        if let selected = snapshot.selected {
                            Text(selected.branch ?? AppLocalization.text("分离 HEAD")).foregroundStyle(.secondary)
                        }
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
        let splitDiff = SplitDiff.parse(model.detail)
        return VStack(spacing: 0) {
            HStack {
                if let file = model.selectedFile {
                    Text(file.path).font(.headline).lineLimit(1)
                    Spacer()
                    Picker("Diff", selection: $model.diffMode) {
                        ForEach(DiffMode.allCases) { mode in Text(LocalizedStringKey(mode.rawValue)).tag(mode) }
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
                        ForEach(DetailLayout.allCases) { layout in Text(LocalizedStringKey(layout.rawValue)).tag(layout) }
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
                Text(model.detail.isEmpty ? AppLocalization.text("选择左侧项目查看详情。") : model.detail)
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
                        Button(AppLocalization.text("Project · %@", project.name)) {
                            model.selectProject(project.id); model.showQuickSwitch = false
                        }
                    }
                    ForEach(project.worktreeGroups) { group in
                        if quickQuery.isEmpty || group.name.localizedCaseInsensitiveContains(quickQuery) || project.name.localizedCaseInsensitiveContains(quickQuery) {
                            Button(AppLocalization.text("%@ / %@", project.name, displayWorktreeGroupName(group.name))) {
                                model.selectProject(project.id)
                                model.selectWorktreeGroup(group.id)
                                model.showQuickSwitch = false
                            }
                        }
                    }
                    ForEach(project.repositories) { repository in
                        if repository.name.localizedCaseInsensitiveContains(quickQuery) {
                            Button(AppLocalization.text("Repository · %@", repository.name)) {
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

    private func displayWorktreeGroupName(_ name: String) -> String {
        switch name {
        case "主目录", "默认": AppLocalization.text(name)
        default: name
        }
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
                Text(LocalizedStringKey(title)).font(.headline)
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
                    ContentUnavailableView(AppLocalization.text(value.message ?? "此图片格式无法预览"), systemImage: "photo")
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
            Text(LocalizedStringKey(title)).font(.title2.bold())
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
