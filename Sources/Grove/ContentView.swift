import SwiftUI

private struct WorktreeRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RepositoryRowFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct RepositoryGroupFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
                .appFont(size: 13, weight: .medium)
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

// Shared by branch and worktree pickers so long lists have a bounded viewport.
private struct PickerContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 360
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct PickerScrollView<Content: View>: View {
    var width: CGFloat = 360
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 360

    var body: some View {
        ScrollView {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PickerContentHeight.self, value: geometry.size.height)
                    }
                }
        }
        .frame(width: width, height: min(360, max(40, contentHeight)))
        .onPreferenceChange(PickerContentHeight.self) { contentHeight = $0 }
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
            PickerScrollView(width: 320) {
                VStack(alignment: .leading, spacing: 4) { content() }
                    .buttonStyle(PickerChoiceStyle { isMenuOpen = false })
                    .appFont(size: 12)
                    .padding(8)
            }
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
        .buttonStyle(WorkbenchHoverButtonStyle())
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
                Image(systemName: icon).appFont(size: 12)
                    .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                Text(AppLocalization.text(title))
                if let count {
                    Text("\(count)")
                        .appFont(size: 10, weight: .semibold, design: .monospaced)
                        .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(selected ? WorkbenchStyle.accent.opacity(0.15) : WorkbenchStyle.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .appFont(size: 12, weight: selected ? .semibold : .regular)
            .foregroundStyle(selected ? Color.primary : WorkbenchStyle.muted)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(selected ? WorkbenchStyle.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(WorkbenchHoverButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

enum DetailLayout: String, CaseIterable, Identifiable {
    case split = "并排模式"
    case patch = "统一内联"
    case preview = "阅读预览"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @FocusState private var focusedCommitScopeID: UUID?
    @FocusState private var changesListFocused: Bool
    @State private var nameAction: NameAction?
    @State private var commitTarget: RepositorySnapshot?
    @State private var remoteTarget: RemoteOperationTarget?
    @State private var nameInput = ""
    @State private var fileQuery = ""
    @State private var showingFilePreview = false
    @State private var previewOrigin = DiffPreviewOrigin()
    @State private var fileFilter: FileChangeFilter = .all
    @State private var quickQuery = ""
    @State private var quickSelection = 0
    @State private var showMergeRequestPicker = false
    @State private var showProjectManagement = false
    @State private var collapsedRepositoryGroups: Set<UUID> = []
    @State private var collapsedChangeRepositories: Set<UUID> = []
    @State private var draggingWorktreeGroup: UUID?
    @State private var draggingWorktreeProject: UUID?
    @State private var worktreeDragOffset: CGFloat = 0
    @State private var worktreeRowFrames: [UUID: CGRect] = [:]
    @State private var draggingRepository: UUID?
    @State private var draggingRepositoryGroup: UUID?
    @State private var repositoryDragProject: UUID?
    @State private var repositoryDragOffset: CGFloat = 0
    @State private var repositoryFrames: [UUID: CGRect] = [:]
    @State private var repositoryGroupFrames: [UUID: CGRect] = [:]
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize

    private var initialSidebarWidth: CGFloat {
        let scale = AppTypography.scale(for: fontSize)
        let names = (model.selectedProject?.worktreeGroups.map(\.name) ?? [])
            + (model.selectedProject?.repositories.map(\.name) ?? [])
            + (model.selectedProject?.groups.map(\.name) ?? [])
        let font = NSFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let textWidth = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(420 * scale, max(280, textWidth + 92 * scale))
    }

    var body: some View {
        SidebarSplitView(initialWidth: initialSidebarWidth) {
            sidebar
                .frame(minWidth: 220, idealWidth: initialSidebarWidth, maxWidth: .infinity)
                .environmentObject(model)
        } content: {
            if let error = model.configurationError {
                VStack(spacing: 16) {
                    ContentUnavailableView(AppLocalization.text("工程配置无法读取"), systemImage: "exclamationmark.triangle", description: Text(error))
                    if model.canRecoverConfiguration {
                        Button(AppLocalization.text("恢复最近的有效备份")) { model.recoverConfiguration(useBackup: true) }
                    }
                    Button(AppLocalization.text("保留损坏文件并重新开始")) { model.recoverConfiguration(useBackup: false) }
                }.padding()
            } else if model.selectedProject == nil {
                ContentUnavailableView("还没有工程", systemImage: "externaldrive", description: Text("从标题栏创建工程，再添加本地 Git 仓库。"))
            } else {
                mainArea.environmentObject(model)
            }
        }
        .overlay {
            if model.showQuickSwitch {
                ZStack {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { model.showQuickSwitch = false }

                    quickSwitch
                        .frame(width: 520, height: 440)
                        .padding(16)
                        .background(WorkbenchStyle.sidebar)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkbenchStyle.border))
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
                        Text("⌘K").appFont(size: 11, design: .monospaced).foregroundStyle(WorkbenchStyle.muted)
                    }
                }
                .buttonStyle(WorkbenchButtonStyle())
                .help("搜索工程、工作树组或仓库 (⌘K)")
                HStack(spacing: 0) { mergeRequestMenu }
            }
        }
        .onChange(of: model.listFocusRequest) { _, _ in
            if model.activeTab == 0 { changesListFocused = true }
            else { focusedCommitScopeID = model.currentCommitScope.id }
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
            .background(WorkbenchStyle.sidebar)
        }
        .sheet(isPresented: $showProjectManagement) {
            ProjectManagementView().environmentObject(model)
        }
        .sheet(item: $remoteTarget) { target in
            RemoteOperationView(target: target).environmentObject(model)
        }
        .sheet(item: $commitTarget) { target in
            CommitReviewView(target: target).environmentObject(model)
        }
        .alert(model.error == nil ? "工作树已变化" : "无法完成操作",
               isPresented: Binding(get: { model.error != nil || model.notice != nil },
                                    set: { if !$0 { model.error = nil; model.notice = nil } })) {
            Button("好") { model.error = nil; model.notice = nil }
        } message: { Text(model.error ?? model.notice ?? "") }
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
                                    .offset(y: draggingWorktreeGroup == group.id ? worktreeDragOffset : 0)
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear.preference(key: WorktreeRowFrames.self,
                                                value: [group.id: geometry.frame(in: .named("worktreeGroups"))])
                                        }
                                    }
                                    .zIndex(draggingWorktreeGroup == group.id ? 1 : 0)
                                    .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("worktreeGroups"))
                                        .onChanged { value in
                                            draggingWorktreeGroup = group.id
                                            draggingWorktreeProject = project.id
                                            worktreeDragOffset = value.translation.height
                                        }
                                        .onEnded { value in
                                            worktreeDragOffset = value.translation.height
                                            finishWorktreeDrag(group.id, projectID: project.id)
                                        })
                            }
                            if !project.hiddenBranches.isEmpty {
                                Menu("恢复隐藏的分支组") {
                                    ForEach(project.hiddenBranches, id: \.self) { branch in
                                        Button(branch) { model.restoreBranch(branch) }
                                    }
                                }
                                .appFont(size: 11)
                                .workbenchHoverFeedback()
                            }
                        }
                        .coordinateSpace(name: "worktreeGroups")
                        .onPreferenceChange(WorktreeRowFrames.self) { worktreeRowFrames = $0 }
                        VStack(alignment: .leading, spacing: 6) {
                            sidebarHeader("关联仓库", action: .repositoryGroup)
                            ForEach(project.groups) { group in
                                repositoryGroupRow(group, in: project)
                                    .offset(y: draggingRepositoryGroup == group.id ? repositoryDragOffset : 0)
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear.preference(key: RepositoryGroupFrames.self,
                                                value: [group.id: geometry.frame(in: .named("repositories"))])
                                        }
                                    }
                                    .zIndex(draggingRepositoryGroup == group.id ? 2 : 0)
                                    .overlay(alignment: repositoryGroupBefore(group.id) ? .top : .bottom) {
                                        if repositoryGroupTarget == group.id && draggingRepositoryGroup != group.id {
                                            insertionLine
                                        }
                                    }
                                    .animation(.easeInOut(duration: 0.12), value: repositoryGroupTarget)
                            }
                        }
                        .coordinateSpace(name: "repositories")
                        .onPreferenceChange(RepositoryRowFrames.self) { repositoryFrames = $0 }
                        .onPreferenceChange(RepositoryGroupFrames.self) { repositoryGroupFrames = $0 }
                    }
                }
                .padding(8)
            }
            HStack(spacing: 6) {
                Circle().fill(model.isRefreshing ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(model.isRefreshing ? "正在刷新本地状态" : "本地仓库 · 前台每 10 秒刷新")
                Spacer(minLength: 0)
                Text(model.isSwitchingBranch ? "正在切换分支…" : "本地 Git")
            }
            .appFont(size: 10)
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
                            .appFont(size: 10, weight: .semibold)
                            .frame(width: 16)
                        Text(LocalizedStringKey(group.name)).lineLimit(1)
                        Text("(\(repositories.count))")
                            .appFont(size: 10, design: .monospaced)
                        Spacer(minLength: 0)
                    }
                    .appFont(size: 11, weight: .medium)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WorkbenchHoverButtonStyle())
                .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("repositories"))
                    .onChanged { value in
                        draggingRepositoryGroup = group.id; repositoryDragProject = project.id
                        repositoryDragOffset = value.translation.height
                    }
                    .onEnded { value in
                        repositoryDragOffset = value.translation.height
                        finishRepositoryGroupDrag(group.id, projectID: project.id)
                    })
                .accessibilityLabel(AppLocalization.text(expanded ? "收起仓库组 %@" : "展开仓库组 %@", group.name))
                IconActionButton(systemName: "folder.badge.plus", hint: AppLocalization.text("导入仓库到%@", group.name)) {
                    chooseRepositories(for: group.id)
                }
            }
            .padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(draggingRepositoryGroup == group.id ? WorkbenchStyle.accent : .clear))
            .contextMenu {
                Button("删除仓库组") { model.removeRepositoryGroup(group.id) }
            }
            if expanded {
                ForEach(repositories) { repository in
                    repositoryRow(repository)
                        .offset(y: draggingRepository == repository.id ? repositoryDragOffset : 0)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: RepositoryRowFrames.self,
                                    value: [repository.id: geometry.frame(in: .named("repositories"))])
                            }
                        }
                        .zIndex(draggingRepository == repository.id ? 1 : 0)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(draggingRepository == repository.id ? WorkbenchStyle.accent : .clear))
                        .overlay(alignment: repositoryBefore(repository.id) ? .top : .bottom) {
                            if repositoryTarget == repository.id && draggingRepository != repository.id { insertionLine }
                        }
                        .animation(.easeInOut(duration: 0.12), value: repositoryTarget)
                }
            }
        }
    }

    private var insertionLine: some View {
        Capsule().fill(WorkbenchStyle.accent).frame(height: 2).padding(.horizontal, 5)
            .allowsHitTesting(false).transition(.opacity)
    }

    private var repositoryTarget: UUID? {
        guard let id = draggingRepository, let project = model.selectedProject,
              let source = project.repositories.first(where: { $0.id == id }), let frame = repositoryFrames[id] else { return nil }
        let position = frame.midY + repositoryDragOffset
        return project.repositories.filter { $0.groupID == source.groupID && repositoryFrames[$0.id] != nil }.min {
            abs(repositoryFrames[$0.id]!.midY - position) < abs(repositoryFrames[$1.id]!.midY - position)
        }?.id
    }

    private var repositoryGroupTarget: UUID? {
        guard let id = draggingRepositoryGroup, let project = model.selectedProject,
              let frame = repositoryGroupFrames[id] else { return nil }
        let position = frame.minY + 14 + repositoryDragOffset
        return project.groups.filter { repositoryGroupFrames[$0.id] != nil }.min {
            abs(repositoryGroupFrames[$0.id]!.minY + 14 - position) < abs(repositoryGroupFrames[$1.id]!.minY + 14 - position)
        }?.id
    }

    private func repositoryBefore(_ id: UUID) -> Bool {
        guard let repositories = model.selectedProject?.repositories,
              let source = repositories.firstIndex(where: { $0.id == draggingRepository }),
              let target = repositories.firstIndex(where: { $0.id == id }) else { return false }
        return target < source
    }

    private func repositoryGroupBefore(_ id: UUID) -> Bool {
        guard let groups = model.selectedProject?.groups,
              let source = groups.firstIndex(where: { $0.id == draggingRepositoryGroup }),
              let target = groups.firstIndex(where: { $0.id == id }) else { return false }
        return target < source
    }

    private func finishRepositoryGroupDrag(_ id: UUID, projectID: UUID) {
        let target = repositoryGroupTarget
        withAnimation(.easeInOut(duration: 0.2)) {
            if draggingRepositoryGroup == id, repositoryDragProject == projectID,
               model.selectedProjectID == projectID, let target { model.reorderRepositoryGroup(id, relativeTo: target) }
            draggingRepositoryGroup = nil; repositoryDragProject = nil; repositoryDragOffset = 0
        }
    }

    private func finishRepositoryDrag(_ id: UUID, projectID: UUID) {
        let target = repositoryTarget
        withAnimation(.easeInOut(duration: 0.2)) {
            if draggingRepository == id, repositoryDragProject == projectID,
               model.selectedProjectID == projectID, let target { model.reorderRepository(id, relativeTo: target) }
            draggingRepository = nil; repositoryDragProject = nil; repositoryDragOffset = 0
        }
    }

    private func worktreeRow(_ group: WorktreeGroup) -> some View {
        let selected = model.selectedWorktreeGroupID == group.id
        return Button { model.selectWorktreeGroup(group.id) } label: {
            HStack(spacing: 6) {
                Group {
                    if group.isPrimary {
                        Image(systemName: "house")
                            .appFont(size: 13)
                    } else {
                        WorkbenchBranchSymbol()
                            .stroke(style: StrokeStyle(lineWidth: 1.5 * AppTypography.scale(for: fontSize), lineCap: .round, lineJoin: .round))
                            .frame(width: 14 * AppTypography.scale(for: fontSize), height: 14 * AppTypography.scale(for: fontSize))
                    }
                }
                    .frame(width: 16 * AppTypography.scale(for: fontSize))
                    .foregroundStyle(selected ? Color.white : WorkbenchStyle.muted)
                Text(LocalizedStringKey(group.name)).lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Text(AppLocalization.text("%ld repos", model.snapshots.filter { !$0.isFallback }.count))
                        .appFont(size: 10, weight: .semibold)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .appFont(size: 12, weight: selected ? .medium : .regular)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(selected ? WorkbenchStyle.selection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkbenchHoverButtonStyle())
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(draggingWorktreeGroup == group.id ? WorkbenchStyle.accent : .clear))
        .overlay(alignment: worktreeInsertionBefore(group.id) ? .top : .bottom) {
            if worktreeDragTarget == group.id && draggingWorktreeGroup != group.id {
                Capsule().fill(WorkbenchStyle.accent)
                    .frame(height: 2).padding(.horizontal, 5)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: worktreeDragTarget)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            Button("上移") { moveWorktreeGroup(group.id, down: false) }
                .disabled(model.selectedProject?.worktreeGroups.first?.id == group.id)
            Button("下移") { moveWorktreeGroup(group.id, down: true) }
                .disabled(model.selectedProject?.worktreeGroups.last?.id == group.id)
            Divider()
            if let branch = group.branch {
                CopyBranchNameButton(branch: branch)
                if !group.isPrimary { Divider() }
            }
            if !group.isPrimary {
                Button("删除工作树组", role: .destructive) { model.removeWorktreeGroup(group.id) }
            }
        }
    }

    private func moveWorktreeGroup(_ id: UUID, down: Bool) {
        guard let groups = model.selectedProject?.worktreeGroups,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        model.moveWorktreeGroups(from: IndexSet(integer: index), to: down ? index + 2 : index - 1)
    }

    private var worktreeDragTarget: UUID? {
        guard let id = draggingWorktreeGroup, let groups = model.selectedProject?.worktreeGroups,
              let frame = worktreeRowFrames[id] else { return nil }
        let position = frame.midY + worktreeDragOffset
        return groups.filter { worktreeRowFrames[$0.id] != nil }.min {
            abs(worktreeRowFrames[$0.id]!.midY - position) < abs(worktreeRowFrames[$1.id]!.midY - position)
        }?.id
    }

    private func worktreeInsertionBefore(_ id: UUID) -> Bool {
        guard let groups = model.selectedProject?.worktreeGroups,
              let source = groups.firstIndex(where: { $0.id == draggingWorktreeGroup }),
              let target = groups.firstIndex(where: { $0.id == id }) else { return false }
        return target < source
    }

    private func finishWorktreeDrag(_ id: UUID, projectID: UUID) {
        defer { draggingWorktreeGroup = nil; draggingWorktreeProject = nil; worktreeDragOffset = 0 }
        guard draggingWorktreeGroup == id, draggingWorktreeProject == projectID,
              model.selectedProjectID == projectID, let groups = model.selectedProject?.worktreeGroups,
              let source = groups.firstIndex(where: { $0.id == id }), let targetID = worktreeDragTarget,
              let target = groups.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            model.moveWorktreeGroups(from: IndexSet(integer: source), to: target > source ? target + 1 : target)
            draggingWorktreeGroup = nil
            draggingWorktreeProject = nil
            worktreeDragOffset = 0
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
            Button("管理工程…") { showProjectManagement = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .foregroundStyle(WorkbenchStyle.accent)
                Text(model.selectedProject?.name ?? "选择工程")
                    .appFont(size: 12, weight: .medium)
                    .lineLimit(1).truncationMode(.middle)
                if let count = model.selectedProject?.repositories.count {
                    Text(AppLocalization.text("%ld repositories", count))
                        .appFont(size: 10, weight: .medium)
                        .foregroundStyle(WorkbenchStyle.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(WorkbenchStyle.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(size: 9, weight: .semibold)
                    .foregroundStyle(WorkbenchStyle.muted)
            }
            .appFont(size: 12, weight: .medium)
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
                .appFont(size: 12, weight: .bold)
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
        let isSelected = model.browsingRepositoryID == repository.id
        let snapshot = model.snapshots.first { $0.repository.id == repository.id }
        return VStack(alignment: .leading, spacing: 0) {
            Button { model.selectBrowsingRepository(repository.id) } label: {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(WorkbenchStyle.repositoryColor(repository.name))
                        .frame(width: 6, height: 6)
                        .frame(width: 16, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.name).appFont(size: 12, weight: .regular).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let count = snapshot?.files.count, count > 0 {
                        Text("\(count)")
                            .appFont(size: 10, design: .monospaced).foregroundStyle(isSelected ? Color.white : WorkbenchStyle.accent)
                    }
                }
                .padding(.leading, 26)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("repositories"))
                .onChanged { value in
                    guard let projectID = model.selectedProjectID else { return }
                    draggingRepository = repository.id; repositoryDragProject = projectID
                    repositoryDragOffset = value.translation.height
                }
                .onEnded { value in
                    guard let projectID = repositoryDragProject else { return }
                    repositoryDragOffset = value.translation.height
                    finishRepositoryDrag(repository.id, projectID: projectID)
                })
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            if let selected = snapshot?.selected {
                HStack(spacing: 4) {
                    BranchPicker(repositoryID: repository.id, worktree: selected)
                        .appFont(size: 10, design: .monospaced).foregroundStyle(isSelected ? Color.white.opacity(0.8) : WorkbenchStyle.muted)
                    Spacer(minLength: 0)
                    WorkbenchMenu(title: "选择工作树", arrowEdge: .leading) {
                        Button("恢复自动匹配") { model.selectWorktree(nil, for: repository.id) }
                        Divider()
                        ForEach(snapshot?.worktrees ?? []) { worktree in
                            Button { model.selectWorktree(worktree.path, for: repository.id) } label: {
                                HStack {
                                    Text(AppLocalization.text("%@ · %@", worktree.branch ?? AppLocalization.text("分离 HEAD"), worktree.isPrimary ? AppLocalization.text("主目录") : URL(fileURLWithPath: worktree.path).lastPathComponent))
                                    if selected.path == worktree.path { Image(systemName: "checkmark") }
                                }
                            }
                            .finderContextMenu(path: worktree.path)
                        }
                    } label: {
                        WorkbenchBranchSymbol()
                            .stroke(style: StrokeStyle(lineWidth: 1.5 * AppTypography.scale(for: fontSize), lineCap: .round, lineJoin: .round))
                            .frame(width: 14 * AppTypography.scale(for: fontSize), height: 14 * AppTypography.scale(for: fontSize))
                            .frame(width: 24, height: 22)
                    }
                    .help("选择工作树")
                }
                .padding(.leading, 48).padding(.trailing, 10).padding(.bottom, 6)
            }
        }
        .background(isSelected ? WorkbenchStyle.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .workbenchHoverFeedback()
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusEffectDisabled()
        .contextMenu {
            if let snapshot {
                ForEach(RemoteOperation.allCases) { operation in
                    Button(operation.title + "…") { remoteTarget = RemoteOperationTarget(snapshot: snapshot, operation: operation) }
                        .disabled(snapshot.selected == nil || model.isOperatingRemote(in: snapshot))
                }
                Divider()
            }
            FinderMenuItem(path: snapshot?.selected?.path ?? repository.path)
            Divider()
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
                    .appFont(size: 11, weight: .medium, design: .monospaced)
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
            (model.browsingRepositoryID == nil || $0.repository.id == model.browsingRepositoryID) && $0.mergeRequestURL != nil
        })
        .help("选择仓库，在浏览器中打开 GitLab 创建页面")
        .popover(isPresented: $showMergeRequestPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("选择仓库创建 MR")
                    .appFont(size: 12, weight: .semibold)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                Divider()
                ForEach(model.snapshots.filter {
                    model.browsingRepositoryID == nil || $0.repository.id == model.browsingRepositoryID
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
                                Text(snapshot.repository.name).appFont(size: 12, weight: .medium)
                                Text(snapshot.mergeRequestURL == nil ? "无可用分支或 GitLab 远端" : snapshot.selected?.branch ?? "")
                                    .appFont(size: 10, design: .monospaced)
                                    .foregroundStyle(WorkbenchStyle.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").appFont(size: 11)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WorkbenchHoverButtonStyle())
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
                ZStack {
                    RetainedPane(isActive: model.activeTab == 0) {
                        changesList.environmentObject(model)
                    }
                    RetainedPane(isActive: model.activeTab == 1) {
                        commitsList.environmentObject(model)
                    }
                }
                .frame(minWidth: 280, idealWidth: model.activeTab == 1 ? 700 * AppTypography.scale(for: fontSize) : 340)
                detailPane
            }
            HStack {
                Text(AppLocalization.text("%ld repositories · %ld changed files", model.snapshots.count, model.snapshots.reduce(0) { $0 + $1.files.count }))
                Spacer()
                if model.browsingRepositoryID != nil {
                    Button("显示全部仓库") { model.selectBrowsingRepository(nil) }.buttonStyle(WorkbenchHoverButtonStyle())
                        .foregroundStyle(WorkbenchStyle.accent)
                }
            }
            .appFont(size: 10)
            .foregroundStyle(WorkbenchStyle.muted)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(WorkbenchStyle.sidebar)
            .overlay(alignment: .top) { Divider() }
        }
        .background(WorkbenchStyle.background)
    }

    private func contentTab(_ title: String, icon: String, count: Int?, index: Int) -> some View {
        WorkbenchTabButton(title: AppLocalization.text(title), icon: icon, count: count, selected: model.activeTab == index) {
            model.activeTab = index
        }
    }

    private var filteredFiles: [ChangedFile] {
        model.snapshots.filter { model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID }
            .flatMap(\.files).filter { matchesFile($0) }
    }

    private func matchesFile(_ file: ChangedFile) -> Bool {
        fileFilter.includes(file) && (fileQuery.isEmpty || file.path.localizedCaseInsensitiveContains(fileQuery))
    }

    private var changesList: some View {
        VStack(spacing: 0) {
            HStack {
                WorkbenchSearchField(title: "筛选文件路径或名称", text: $fileQuery)
                WorkbenchPicker(title: "修改类型", values: FileChangeFilter.allCases, selection: $fileFilter) {
                    AppLocalization.text($0.rawValue)
                }.fixedSize(horizontal: true, vertical: false)
                if fileFilter != .all {
                    Button { fileQuery = ""; fileFilter = .all } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(WorkbenchButtonStyle(size: .compact))
                        .help(AppLocalization.text("清除筛选"))
                        .accessibilityLabel(AppLocalization.text("清除筛选"))
                }
            }.padding(10)
            Divider()
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.snapshots.filter { model.focusedRepositoryID == nil || $0.repository.id == model.focusedRepositoryID }) { snapshot in
                    repositoryChangeHeader(snapshot)
                    if !collapsedChangeRepositories.contains(snapshot.repository.id) {
                        if let error = snapshot.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).appFont(size: 11).foregroundStyle(.red).textSelection(.enabled)
                                Button(AppLocalization.text("重试读取")) { model.refresh(useCachedHistory: true, changedPaths: [snapshot.repository.path]) }
                                    .disabled(model.isRefreshing)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 28).padding(.vertical, 10)
                        } else if !snapshot.files.isEmpty {
                            LazyVStack(spacing: 2) {
                                ForEach(snapshot.files.filter { matchesFile($0) }) { file in
                                    Button { model.selectFile(file) } label: {
                                        ChangedFileRow(file: file, selected: model.selectedFile?.id == file.id)
                                    }
                                    .buttonStyle(WorkbenchHoverButtonStyle())
                                    .background(DiffPreviewAnchor(origin: previewOrigin, id: file.id))
                                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                        if model.detailStates[0].selectedFile?.id != file.id { model.selectFile(file) }
                                        showingFilePreview = true
                                    })
                                    .id(file.id)
                                    .fileContextMenu(path: snapshot.selected.map {
                                        URL(fileURLWithPath: $0.path).appendingPathComponent(file.path).path
                                    }, filePath: file.path)
                                }
                            }
                            .padding(.leading, 16).padding(.trailing, 6)
                            .padding(.top, 6).padding(.bottom, 12)
                        }
                    }
                }
            }
        }
        .focusable().focused($changesListFocused).focusEffectDisabled()
        .onKeyPress(.space) {
            guard model.detailStates[0].selectedFile != nil else { return .ignored }
            showingFilePreview = true
            return .handled
        }
        .onKeyPress(.downArrow) { moveFile(1); return .handled }
        .onKeyPress(.upArrow) { moveFile(-1); return .handled }
        .onChange(of: model.detailStates[0].selectedFile?.id) { _, id in if let id { proxy.scrollTo(id) } }
        }
        if filteredFiles.isEmpty && (!fileQuery.isEmpty || fileFilter != .all) {
            Text(AppLocalization.text("没有匹配的文件")).foregroundStyle(.secondary).padding()
        }
        }
        .frame(minWidth: 280, idealWidth: 340)
        .background(WorkbenchStyle.background)
        .background {
            DiffPreviewWindow(isPresented: $showingFilePreview, moveFile: moveFile,
                              onClose: { changesListFocused = true },
                              origin: previewOrigin, selectionID: model.detailStates[0].selectedFile?.id) {
                VStack(spacing: 0) {
                    DiffPreviewToolbar(position: previewFiles.firstIndex { $0.id == model.detailStates[0].selectedFile?.id } ?? -1,
                                       count: previewFiles.count, moveFile: moveFile,
                                       close: { showingFilePreview = false })
                    Divider()
                    DetailPaneView(state: model.detailStates[0], tab: 0, isPreview: true)
                        .environmentObject(model)
                }.background(WorkbenchStyle.background)
            }
        }
        .onChange(of: model.detailStates[0].selectedFile?.id) { _, id in
            if id == nil { showingFilePreview = false }
        }
    }

    private var previewFiles: [ChangedFile] {
        filteredFiles.filter { !collapsedChangeRepositories.contains($0.repositoryID) }
    }

    private func moveFile(_ delta: Int) {
        let files = previewFiles
        guard !files.isEmpty else { return }
        let current = files.firstIndex { $0.id == model.detailStates[0].selectedFile?.id }
        let next = current.map { min(max(0, $0 + delta), files.count - 1) } ?? (delta > 0 ? 0 : files.count - 1)
        model.selectFile(files[next])
    }

    private func repositoryChangeHeader(_ snapshot: RepositorySnapshot) -> some View {
        let repositoryID = snapshot.repository.id
        let collapsed = collapsedChangeRepositories.contains(repositoryID)
        let hasContent = !snapshot.files.isEmpty || snapshot.error != nil
        let conflicts = snapshot.files.filter { $0.changeKind == .conflict }.count
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button { toggleRepository() } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .appFont(size: 9, weight: .semibold)
                    .foregroundStyle(WorkbenchStyle.muted)
                    .frame(width: 12)
                    .opacity(hasContent ? 1 : 0)
            }
            .disabled(!hasContent)
            VStack(alignment: .leading, spacing: 3) {
                Button { toggleRepository() } label: {
                    Text(snapshot.repository.name)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(!hasContent)
                HStack(spacing: 6) {
                    if let selected = snapshot.selected {
                        BranchPicker(repositoryID: repositoryID, worktree: selected)
                    }
                    if snapshot.isFallback {
                        Text("共享主目录").foregroundStyle(.orange).fixedSize()
                    }
                }
                .appFont(size: 10).foregroundStyle(WorkbenchStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Button { toggleRepository() } label: {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(snapshot.error != nil ? AppLocalization.text("读取失败") :
                             snapshot.files.isEmpty ? AppLocalization.text("无修改") :
                             AppLocalization.text("%ld changes", snapshot.files.count))
                            .foregroundStyle(snapshot.error != nil ? Color.red : WorkbenchStyle.muted)
                        if conflicts > 0 {
                            Text(AppLocalization.text("%ld conflicts", conflicts)).foregroundStyle(.red)
                        }
                    }
                    .appFont(size: 10).fixedSize()
                }
                .disabled(!hasContent)
                HStack(spacing: 4) {
                    RepositoryRemoteActions(snapshot: snapshot) { operation in
                        remoteTarget = RemoteOperationTarget(snapshot: snapshot, operation: operation)
                    }
                    Button { commitTarget = snapshot } label: {
                        Image(systemName: "square.and.pencil")
                            .appFont(size: 12).frame(width: 28, height: 26)
                    }
                    .buttonStyle(WorkbenchHoverButtonStyle())
                    .help("准备提交…")
                    .accessibilityLabel("准备提交…")
                    .disabled(snapshot.files.isEmpty || snapshot.error != nil || conflicts > 0 || snapshot.selected?.branch == nil
                              || model.isCommitting || model.isSwitchingBranch || model.isDiscarding || model.isOperatingRemote)
                }
            }
        }
        .buttonStyle(WorkbenchHoverButtonStyle())
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchStyle.sidebar)
        .workbenchHoverFeedback(enabled: hasContent)
        .overlay(alignment: .top) { Rectangle().fill(WorkbenchStyle.border.opacity(0.65)).frame(height: 1) }
        .contentShape(Rectangle())
        .finderContextMenu(path: snapshot.selected?.path ?? snapshot.repository.path)

        func toggleRepository() {
            guard hasContent else { return }
            if collapsed { collapsedChangeRepositories.remove(repositoryID) }
            else { collapsedChangeRepositories.insert(repositoryID) }
        }
    }

    private var commitsList: some View {
        VStack(spacing: 0) {
            WorkbenchMenu(title: "选择提交记录仓库") {
                Button { model.selectCommitRepository(nil) } label: {
                    HStack {
                        Text("全部仓库")
                        Spacer()
                        if model.commitRepositoryID == nil { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach(model.selectedProject?.repositories ?? []) { repository in
                    Button { model.selectCommitRepository(repository.id) } label: {
                        HStack {
                            Text(repository.name)
                            Spacer()
                            if model.commitRepositoryID == repository.id { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(!model.snapshots.contains { $0.repository.id == repository.id && $0.selected != nil })
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.selectedProject?.repositories.first { $0.id == model.commitRepositoryID }?.name ?? AppLocalization.text("全部仓库"))
                            .appFont(size: 12, weight: .semibold)
                        if let snapshot = model.snapshots.first(where: { $0.repository.id == model.commitRepositoryID }) {
                            Text(snapshot.selected?.branch ?? AppLocalization.text("分离 HEAD"))
                                .appFont(size: 10, design: .monospaced).foregroundStyle(WorkbenchStyle.muted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").appFont(size: 10)
                }
                .padding(12)
            }
            Divider()
            ZStack {
                ForEach(model.commitScopes) { scope in
                    RetainedPane(isActive: scope.repositoryID == model.commitRepositoryID && model.activeTab == 1) {
                        commitList(scope).environmentObject(model)
                    }
                }
            }
        }
        .frame(minWidth: 280,
               idealWidth: model.activeTab == 1 ? 700 * AppTypography.scale(for: fontSize) : 340)
        .background(WorkbenchStyle.background)
        .onChange(of: model.commitRepositoryID) { _, _ in
            if model.activeTab == 1 { focusedCommitScopeID = model.currentCommitScope.id }
        }
        .onChange(of: model.activeTab) { _, tab in
            focusedCommitScopeID = tab == 1 ? model.currentCommitScope.id : nil
        }
    }

    private func commitList(_ scope: CommitBrowserScope) -> some View {
        let commits = model.commits.filter { scope.repositoryID == nil || $0.repositoryID == scope.repositoryID }
        let query = scope.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !query.isEmpty
        let source = searching && scope.searchLocalHistory ? scope.searchResults : commits
        let prepared = scope.repositoryID.flatMap { model.preparedHistories[$0] }
        let displayedCommits = searching ? source.filter { scope.searchLocalHistory || scope.searchField.matches($0, query: query) }
            : (scope.repositoryID == nil ? commits : prepared?.commits ?? [])
        let graph = !searching ? prepared?.graph : nil
        let graphRows = !searching ? prepared?.rows ?? [:] : [:]
        let scale = AppTypography.scale(for: fontSize)
        return VStack(spacing: 0) {
            historySearchControls(scope)
            Divider()
        GeometryReader { geometry in
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedCommits) { commit in
                        Button { model.selectCommit(commit) } label: {
                            HStack(spacing: 8) {
                                if let graph, let row = graphRows[commit.id] {
                                    CommitGraphCell(row: row, laneCount: graph.laneCount, scale: scale, tracks: graph.tracks)
                                        .frame(height: 30 * scale)
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(commit.subject)
                                        .appFont(size: 12, weight: scope.detail.selectedCommit == commit ? .semibold : .medium)
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .help(commit.subject)
                                    if scope.repositoryID == nil {
                                        let repositoryName = model.selectedProject?.repositories.first(where: { $0.id == commit.repositoryID })?.name ?? AppLocalization.text("仓库")
                                        Text(repositoryName)
                                            .appFont(size: 10).foregroundStyle(WorkbenchStyle.muted)
                                            .lineLimit(1).truncationMode(.middle)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .frame(width: min(90 * AppTypography.scale(for: fontSize), geometry.size.width * 0.15))
                                            .background(WorkbenchStyle.surface, in: RoundedRectangle(cornerRadius: 3))
                                            .help(repositoryName)
                                    }
                                    if geometry.size.width >= 480 * AppTypography.scale(for: fontSize) {
                                        Text(commit.committer)
                                            .appFont(size: 11)
                                            .foregroundStyle(WorkbenchStyle.committerColor(commit.committer))
                                            .lineLimit(1).truncationMode(.tail)
                                            .frame(width: min(90 * AppTypography.scale(for: fontSize), geometry.size.width * 0.17), alignment: .leading)
                                            .help(commit.committer)
                                        Text(commit.formattedDate)
                                            .appFont(size: 10, design: .monospaced)
                                            .foregroundStyle(WorkbenchStyle.muted)
                                            .lineLimit(1).truncationMode(.tail)
                                            .frame(width: min(125 * AppTypography.scale(for: fontSize), geometry.size.width * 0.25), alignment: .leading)
                                            .help(commit.formattedDate)
                                    }
                                    Text(commit.hash.prefix(7))
                                        .appFont(size: 10, design: .monospaced)
                                        .foregroundStyle(WorkbenchStyle.muted)
                                        .fixedSize()
                                        .help(commit.hash)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help("\(commit.subject)\n\(commit.committer) · \(commit.formattedDate)\n\(commit.hash)")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(WorkbenchRowButtonStyle(isSelected: scope.detail.selectedCommit == commit, verticalPadding: scope.repositoryID == nil ? 5 : 0))
                        .id(commit.id)
                    }
                    let failures = model.historyErrors.filter { scope.repositoryID == nil || $0.key == scope.repositoryID }
                    if searching && scope.searchLocalHistory {
                        if scope.isSearching { ProgressView().controlSize(.small).padding() }
                        if let error = scope.searchError {
                            Text(error).foregroundStyle(.red).textSelection(.enabled).padding(8)
                            Button(AppLocalization.text("重试查询")) { Task { await model.searchHistory(scope) } }
                        }
                    } else if !failures.isEmpty {
                        ForEach(failures.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            Text((model.selectedProject?.repositories.first { $0.id == id }?.name ?? "") + ": " + (failures[id] ?? ""))
                                .foregroundStyle(.red).textSelection(.enabled).padding(8)
                        }
                        Button(AppLocalization.text("重试读取")) { model.refresh(useCachedHistory: true) }.disabled(model.isRefreshing)
                    }
                    if displayedCommits.isEmpty && failures.isEmpty && scope.searchError == nil && !scope.isSearching {
                        Text(AppLocalization.text(model.isRefreshing ? "正在读取…" : searching ? "没有匹配的提交" : "暂无提交记录"))
                            .foregroundStyle(WorkbenchStyle.muted).padding(.vertical, 12)
                    }
                    if searching && scope.searchLocalHistory {
                        if scope.searchResults.count >= scope.searchLimit {
                            Button(AppLocalization.text("加载更多匹配记录")) { scope.searchLimit += 50 }.disabled(scope.isSearching)
                        }
                    } else if !model.snapshots.filter({ $0.selected != nil && (scope.repositoryID == nil || $0.repository.id == scope.repositoryID) }).allSatisfy({ model.historyExhausted.contains($0.repository.id) }) {
                        Button("加载更早提交") { model.loadMoreCommits() }
                            .buttonStyle(WorkbenchButtonStyle())
                            .frame(maxWidth: .infinity)
                            .disabled(model.isRefreshing)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(WorkbenchStyle.background)
            .focusable().focused($focusedCommitScopeID, equals: scope.id).focusEffectDisabled()
            .onKeyPress(.downArrow) { moveCommit(1, in: displayedCommits, scope: scope); return .handled }
            .onKeyPress(.upArrow) { moveCommit(-1, in: displayedCommits, scope: scope); return .handled }
            .onChange(of: scope.detail.selectedCommit?.id) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
        }
        .task(id: "\(scope.query)|\(scope.searchField.rawValue)|\(scope.searchLocalHistory)|\(scope.searchLimit)|" + model.snapshots.map { ($0.selected?.path ?? "") + ($0.selected?.head ?? "") }.joined(separator: "|")) {
            await model.searchHistory(scope)
        }
    }

    private func historySearchControls(_ scope: CommitBrowserScope) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WorkbenchSearchField(title: scope.searchField == .path ? "输入完整相对文件路径" : "搜索提交",
                                     text: Binding(get: { scope.query }, set: { scope.query = $0; scope.searchLimit = 50 }))
                WorkbenchPicker(title: "搜索字段", values: HistorySearchField.allCases,
                                selection: Binding(get: { scope.searchField }, set: { scope.searchField = $0; if $0 == .path { scope.searchLocalHistory = true }; scope.searchLimit = 50 })) {
                    AppLocalization.text($0.rawValue)
                }.fixedSize(horizontal: true, vertical: false)
            }
            Toggle(AppLocalization.text("查询本地历史（当前 HEAD 可达，不联网）"), isOn: Binding(get: { scope.searchLocalHistory }, set: { scope.searchLocalHistory = $0; if !$0 && scope.searchField == .path { scope.searchField = .title }; scope.searchLimit = 50 }))
                .toggleStyle(.checkbox)
            Text(AppLocalization.text(scope.searchLocalHistory ? "每个仓库先显示 50 条匹配，可继续加载。路径按完整相对路径查询。" : "仅筛选已加载的记录；更早记录请启用本地历史查询。"))
                .foregroundStyle(.secondary)
        }.appFont(size: 10).padding(10)
    }

    private func moveCommit(_ delta: Int, in commits: [Commit], scope: CommitBrowserScope) {
        guard !commits.isEmpty else { return }
        let current = commits.firstIndex { $0.id == scope.detail.selectedCommit?.id }
        let next = current.map { min(max(0, $0 + delta), commits.count - 1) } ?? (delta > 0 ? 0 : commits.count - 1)
        model.selectCommit(commits[next])
    }

    private var detailPane: some View {
        ZStack {
            RetainedPane(isActive: model.activeTab == 0) {
                DetailPaneView(state: model.detailStates[0], tab: 0)
                    .environmentObject(model)
            }
            ForEach(model.commitScopes) { scope in
                RetainedPane(isActive: model.activeTab == 1 && scope.repositoryID == model.commitRepositoryID) {
                    DetailPaneView(state: scope.detail, tab: 1)
                        .environmentObject(model)
                }
            }
        }
        .frame(minWidth: 430)
    }

    private struct QuickResult: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let projectID: UUID
        var groupID: UUID? = nil
        var repositoryID: UUID? = nil
    }

    private var quickResults: [QuickResult] {
        let query = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [QuickResult] = []
        for project in model.projects {
            let matchesProject = query.isEmpty || project.name.localizedCaseInsensitiveContains(query)
            if matchesProject {
                results.append(QuickResult(id: "project:\(project.id)", title: project.name,
                                           subtitle: AppLocalization.text("工程"), icon: "folder", projectID: project.id))
            }
            for group in project.worktreeGroups where matchesProject || group.name.localizedCaseInsensitiveContains(query) {
                results.append(QuickResult(id: "group:\(group.id)", title: displayWorktreeGroupName(group.name),
                                           subtitle: project.name, icon: "arrow.triangle.branch", projectID: project.id, groupID: group.id))
            }
            for repository in project.repositories where !query.isEmpty && repository.name.localizedCaseInsensitiveContains(query) {
                results.append(QuickResult(id: "repository:\(repository.id)", title: repository.name,
                                           subtitle: project.name, icon: "externaldrive", projectID: project.id, repositoryID: repository.id))
            }
        }
        return results
    }

    private var quickSwitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("快速切换").appFont(size: 15, weight: .semibold)
                Spacer()
                IconActionButton(systemName: "xmark", hint: "关闭") { model.showQuickSwitch = false }
            }
            WorkbenchSearchField(title: "搜索工程、工作树组或仓库", text: $quickQuery, autofocus: true)
                .onSubmit { chooseFirstQuickResult() }
                .onKeyPress(.upArrow) { moveQuickSelection(-1); return .handled }
                .onKeyPress(.downArrow) { moveQuickSelection(1); return .handled }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(quickResults.enumerated()), id: \.element.id) { index, result in
                            Button { chooseQuickResult(result) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: result.icon)
                                        .appFont(size: 14)
                                        .foregroundStyle(WorkbenchStyle.accent)
                                        .frame(width: 30, height: 30)
                                        .background(WorkbenchStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title).appFont(size: 12, weight: .medium).lineLimit(1)
                                        Text(result.subtitle).appFont(size: 10).foregroundStyle(WorkbenchStyle.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    if index == quickSelection {
                                        Image(systemName: "return").appFont(size: 11).foregroundStyle(WorkbenchStyle.accent)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == quickSelection ? WorkbenchStyle.accent.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(WorkbenchHoverButtonStyle())
                            .accessibilityAddTraits(index == quickSelection ? [.isSelected] : [])
                            .id(result.id)
                        }
                        if quickResults.isEmpty {
                            Text("无匹配结果").appFont(size: 12).foregroundStyle(WorkbenchStyle.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 36)
                        }
                    }
                }
                .onChange(of: quickSelection) { _, index in
                    guard quickResults.indices.contains(index) else { return }
                    proxy.scrollTo(quickResults[index].id)
                }
                .onChange(of: quickQuery) { _, _ in
                    quickSelection = 0
                    if let first = quickResults.first { proxy.scrollTo(first.id, anchor: .top) }
                }
            }
            HStack(spacing: 14) {
                Text("↑ ↓  选择")
                Text("↵  打开")
                Spacer()
                Text("esc  关闭")
            }
            .appFont(size: 10).foregroundStyle(WorkbenchStyle.muted)
        }
        .onAppear { quickQuery = ""; quickSelection = 0 }
        .onExitCommand { model.showQuickSwitch = false }
    }

    private func moveQuickSelection(_ offset: Int) {
        quickSelection = min(max(0, quickSelection + offset), max(0, quickResults.count - 1))
    }

    private func chooseQuickResult(_ result: QuickResult) {
        model.selectProject(result.projectID)
        if let groupID = result.groupID { model.selectWorktreeGroup(groupID) }
        if let repositoryID = result.repositoryID { model.selectBrowsingRepository(repositoryID) }
        model.showQuickSwitch = false
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
        guard quickResults.indices.contains(quickSelection) else { return }
        chooseQuickResult(quickResults[quickSelection])
    }

}

private struct ImageDiffView: View {
    let preview: ImageDiffPreview
    let oldTitle: String
    let newTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(changeLabel, systemImage: "photo.on.rectangle")
                .appFont(size: 12)
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
                Text(LocalizedStringKey(title)).appFont(size: 13, weight: .semibold)
                Spacer()
                if let count = value.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file))
                        .appFont(size: 10).foregroundStyle(.secondary)
                }
            }
            ZStack {
                if let svg = value.svgData {
                    SVGPreviewView(data: svg)
                        .frame(maxWidth: 260, maxHeight: 260)
                } else if let data = value.data, let image = NSImage(data: data) {
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
            Text(LocalizedStringKey(title)).appFont(size: 22, weight: .bold)
            WorkbenchTextField(title: "名称", text: $name)
                .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { onSave(name) } }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(WorkbenchButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("创建") { onSave(name) }
                    .buttonStyle(WorkbenchButtonStyle(emphasized: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .background(WorkbenchStyle.sidebar)
    }
}

// Retain visited panes so their selection and native scroll positions survive
// tab switches. RetainedPane freezes hidden viewports during window resizing.
private struct DetailPaneView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var state: DetailState
    let tab: Int
    var isPreview = false
    @State private var detailLayout: DetailLayout = .split
    @State private var resetDetailScrollOnLoad = false
    @StateObject private var discardTargets = DiffDiscardTargets()
    @State private var pendingDiscard: DiffDiscardRequest?
    @State private var showingDiscardConfirmation = false
    @StateObject private var diffSearch = DiffSearch()
    @FocusState private var detailFocused: Bool
    private var isActive: Bool { model.activeTab == tab && (tab == 0 || state === model.currentCommitScope.detail) }

    var body: some View {
        detailPane
            .environment(\.markdownReviewIsActive, isActive)
            .focusable().focused($detailFocused).focusEffectDisabled()
            .onChange(of: model.detailFocusRequest) { _, _ in if isActive { detailFocused = true } }
            .onChange(of: model.nextHunkRequest) { _, _ in if isActive { diffSearch.moveHunk(1) } }
            .onChange(of: model.previousHunkRequest) { _, _ in if isActive { diffSearch.moveHunk(-1) } }
            .onChange(of: model.findRequest) { _, _ in
                guard model.activeTab == tab, tab == 0 || state === model.currentCommitScope.detail else { return }
                if state.selectedFile != nil || state.selectedCommit != nil {
                    if state.imagePreview != nil { detailLayout = .patch } else if detailLayout == .preview { detailLayout = .split }
                    diffSearch.isPresented = true
                }
            }
            .onAppear { discardTargets.prepare(state.splitDiff) }
            .onChange(of: state.splitDiff.contentID) { _, _ in discardTargets.prepare(state.splitDiff) }
            .alert("丢弃所选修改？", isPresented: $showingDiscardConfirmation) {
                Button("取消", role: .cancel) { pendingDiscard = nil }
                Button("丢弃", role: .destructive) {
                    guard let request = pendingDiscard else { return }
                    pendingDiscard = nil
                    Task { await model.discard(request) }
                }
            } message: {
                if let request = pendingDiscard {
                    Text(AppLocalization.text("%@\n%@\n丢弃 %ld 行未暂存修改（替换行包含原行和新行）。已暂存内容保留。此操作无法撤销。",
                                              request.file.path, request.checkoutPath, request.selectedRows.count))
                }
            }
    }

    private var detailPane: some View {
        let splitDiff = state.splitDiff
        return VStack(spacing: 0) {
            if let file = state.selectedFile {
                Text(file.path).appFont(size: 13, weight: .semibold).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 12)
                    .help(file.path)
                    .fileContextMenu(path: filePath(file.path, repositoryID: file.repositoryID), filePath: file.path)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    detailHeading
                    Spacer(minLength: 12)
                    if state.selectedFile != nil || state.selectedCommit != nil { layoutControl }
                }
                VStack(alignment: .leading, spacing: 8) {
                    detailHeading
                    if state.selectedFile != nil || state.selectedCommit != nil { layoutControl }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            if state.selectedFile != nil || state.selectedCommit != nil {
                if diffSearch.isPresented { DiffSearchBar(search: diffSearch) }
                else {
                    HStack {
                        Spacer()
                        Button(AppLocalization.text("查找 / 跳转修改块（⌘F）")) {
                            if state.imagePreview != nil { detailLayout = .patch } else if detailLayout == .preview { detailLayout = .split }
                            diffSearch.isPresented = true
                        }.buttonStyle(WorkbenchHoverButtonStyle()).appFont(size: 10)
                    }.padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
            Divider()
            if let error = state.readError {
                VStack(alignment: .leading, spacing: 12) {
                    Label(AppLocalization.text("读取详情失败"), systemImage: "exclamationmark.triangle")
                    Text(error).textSelection(.enabled).foregroundStyle(.secondary)
                    Button(AppLocalization.text("重试读取")) { model.loadDetail(tab: tab) }
                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let commit = state.selectedCommit, let patch = state.commitPatch, !patch.files.isEmpty {
                CommitDetailView(patch: patch, layout: detailLayout,
                                 checkoutPath: model.snapshots.first { $0.repository.id == commit.repositoryID }?.selected?.path,
                                 commitHash: commit.hash, search: diffSearch)
                    .id(commit.id)
            } else if detailLayout == .preview, let file = state.selectedFile,
                      MarkdownPreview.supports(file.path),
                      let checkout = model.snapshots.first(where: { $0.repository.id == file.repositoryID })?.selected?.path {
                MarkdownReviewView(path: file.path, oldPath: state.filePresentation.oldPath,
                                   checkout: checkout, mode: state.diffMode, untracked: file.isUntracked,
                                   revision: "\(state.generation):\(state.detail)", preferOld: file.changeKind == .deleted,
                                   oldTitle: oldDiffTitle, newTitle: newDiffTitle)
                    .id(file.id + ":" + state.diffMode.rawValue)
            } else if detailLayout != .patch, let preview = state.imagePreview {
                ImageDiffView(preview: preview, oldTitle: oldDiffTitle, newTitle: newDiffTitle)
                    .id(detailScrollIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detailLayout != .patch && splitDiff.hasChanges && !state.filePresentation.hasSummary {
                SplitDiffView(diff: splitDiff, oldTitle: oldDiffTitle, newTitle: newDiffTitle,
                              resetID: detailScrollIdentity, search: diffSearch,
                              discardTargets: canDiscard ? discardTargets : nil,
                              onDiscard: canDiscard ? prepareDiscard : nil)
                    .id(detailScrollIdentity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rawDetail
            }
        }
        .frame(minWidth: 430)
        .background(WorkbenchStyle.background)
    }

    private var canDiscard: Bool {
        !isPreview && tab == 0 && state.diffMode == .unstaged && state.selectedFile != nil
            && state.selectedFile?.changeKind != .conflict && state.imagePreview == nil
            && !model.isDiscarding && !model.isSwitchingBranch
    }

    private func prepareDiscard(_ rows: Set<Int>, contentID: UUID) {
        guard canDiscard, contentID == state.splitDiff.contentID, !rows.isEmpty, let file = state.selectedFile,
              let checkout = model.snapshots.first(where: { $0.repository.id == file.repositoryID })?.selected?.path else { return }
        pendingDiscard = DiffDiscardRequest(file: file, checkoutPath: checkout, patch: state.detail,
                                            selectedRows: rows)
        showingDiscardConfirmation = true
    }

    private func filePath(_ path: String, repositoryID: UUID) -> String? {
        model.snapshots.first { $0.repository.id == repositoryID }?.selected.map {
            URL(fileURLWithPath: $0.path).appendingPathComponent(path).path
        }
    }

    @ViewBuilder private var detailHeading: some View {
        if state.selectedFile != nil {
            WorkbenchSegments(title: "Diff", values: DiffMode.allCases, selection: $state.diffMode) {
                AppLocalization.text($0.rawValue)
            }
            .onChange(of: state.diffMode) { _, _ in model.loadDetail(tab: tab) }
        } else if let commit = state.selectedCommit {
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject).appFont(size: 13, weight: .semibold).lineLimit(1)
                    .textSelection(.enabled)
                    .help(commit.subject)
                    .contextMenu {
                        Button(AppLocalization.text("复制提交标题")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commit.subject, forType: .string)
                        }
                    }
                Text("\(commit.committer) · \(commit.formattedDate)")
                    .appFont(size: 11).foregroundStyle(.secondary)
                    .lineLimit(1).help("\(commit.committer) · \(commit.formattedDate)")
            }
        } else {
            Text(AppLocalization.text("选择文件或提交")).foregroundStyle(.secondary)
        }
    }

    private var markdownAvailable: Bool {
        if let file = state.selectedFile { return MarkdownPreview.supports(file.path) }
        return state.commitPatch?.files.contains { MarkdownPreview.supports($0.path) } == true
    }

    private var layoutControl: some View {
        HStack(spacing: 2) {
            ForEach(DetailLayout.allCases.filter { $0 != .preview || markdownAvailable }) { layout in
                WorkbenchTabButton(title: layout.rawValue,
                                   icon: layout == .preview ? "book" : layout == .split ? "rectangle.split.1x2" : "rectangle.split.2x1",
                                   selected: (detailLayout == .preview && !markdownAvailable ? .split : detailLayout) == layout) {
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

    private var rawDetail: some View {
        SearchablePatchView(text: state.detail.isEmpty ? AppLocalization.text("选择左侧项目查看详情。") : state.detail, search: diffSearch)
            .id(detailScrollIdentity)
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
            Text(AppLocalization.text(file.changeKind.rawValue))
                .appFont(size: 10, weight: .bold, design: .monospaced)
                .foregroundStyle(color)
                .frame(width: 22, height: 20)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            pathLabel
                .appFont(size: 13, weight: selected ? .semibold : .medium)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if file.hasStaged && file.changeKind != .conflict {
                Image(systemName: "checkmark.circle.fill")
                    .appFont(size: 10).foregroundStyle(.secondary)
                    .help(AppLocalization.text(file.hasUnstaged ? "已暂存，另有未暂存修改" : "已暂存"))
            }
            Group {
                if let stats = file.stats {
                    if stats.isBinary {
                        Text(AppLocalization.text("二进制")).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 5) {
                            Text("+\(stats.additions)").foregroundStyle(.green)
                            Text("−\(stats.deletions)").foregroundStyle(.red)
                        }
                        .help(AppLocalization.text("已暂存和未暂存修改的增删行数合计"))
                    }
                } else { Text("—").foregroundStyle(.secondary).help(AppLocalization.text("暂无行数统计")) }
            }
            .appFont(size: 10, design: .monospaced)
            .fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? WorkbenchStyle.surface : Color.clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(WorkbenchStyle.accent).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .help(AppLocalization.text("%@ · %@", file.changeKind.title, file.path))
    }

    private var pathLabel: Text {
        let filename = (file.path as NSString).lastPathComponent
        let directory = String(file.path.dropLast(filename.count))
        return Text(directory).foregroundColor(WorkbenchStyle.muted)
            + Text(filename)
                .foregroundColor(selected ? WorkbenchStyle.accent : .primary)
                .strikethrough(file.changeKind == .deleted)
    }
}
