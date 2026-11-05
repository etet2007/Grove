import SwiftUI

@main struct GroveApp: App {
    var body: some Scene {
        WindowGroup {
            GroveWindow()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            WorktreeCommands()
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

    }
}

private struct GroveWindow: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView()
            .appFont(size: 12)
            .environmentObject(model)
            .focusedSceneValue(\.groveModel, model)
            .background(WindowTitleHider())
            .frame(minWidth: 1000, minHeight: 650)
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                model.automaticRefreshEnabled = phase == .active
                if phase == .active && !model.isRefreshing {
                    model.refresh()
                }
            }
            .task(id: scenePhase) {
                model.automaticRefreshEnabled = scenePhase == .active
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) }
                    catch { return }
                    guard !Task.isCancelled, scenePhase == .active else { return }
                    if !model.isRefreshing { model.refresh(useCachedHistory: true) }
                }
            }
    }
}

private struct WindowTitleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> TitleHidingView { TitleHidingView() }
    func updateNSView(_ view: TitleHidingView, context: Context) {
        view.hideTitle()
    }

    final class TitleHidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideTitle()
        }

        func hideTitle() {
            DispatchQueue.main.async { [weak self] in
                self?.window?.titleVisibility = .hidden
            }
        }
    }
}

private struct GroveModelKey: FocusedValueKey {
    typealias Value = AppModel
}

private extension FocusedValues {
    var groveModel: AppModel? {
        get { self[GroveModelKey.self] }
        set { self[GroveModelKey.self] = newValue }
    }
}

private struct WorktreeCommands: Commands {
    @FocusedValue(\.groveModel) private var model

    var body: some Commands {
            CommandMenu("工作树") {
                Button("快速切换…") { model?.showQuickSwitch = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model == nil)
                Button("刷新") { model?.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model == nil)
                Button("在 diff 中查找…") { model?.findRequest = UUID() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(model == nil)
                Button("聚焦文件或提交列表") { model?.listFocusRequest = UUID() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option]).disabled(model == nil)
                Button("聚焦详情") { model?.detailFocusRequest = UUID() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option]).disabled(model == nil)
                Button("上一个修改块") { model?.previousHunkRequest = UUID() }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(model == nil)
                Button("下一个修改块") { model?.nextHunkRequest = UUID() }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(model == nil)
                Divider()
                ForEach(model?.projects ?? []) { project in
                    Menu(LocalizedStringKey(project.name)) {
                        ForEach(project.worktreeGroups) { group in
                            Menu(LocalizedStringKey(group.name)) {
                                Button("切换整组") {
                                    model?.selectProject(project.id)
                                    model?.selectWorktreeGroup(group.id)
                                }
                                ForEach(project.repositories) { repository in
                                    Menu(LocalizedStringKey(repository.name)) {
                                        if model?.selectedProjectID == project.id,
                                           model?.selectedWorktreeGroupID == group.id,
                                           let snapshot = model?.snapshots.first(where: { $0.repository.id == repository.id }) {
                                            Button("自动匹配") { model?.selectWorktree(nil, for: repository.id) }
                                            ForEach(snapshot.worktrees) { worktree in
                                                Button(AppLocalization.text("%@ · %@", worktree.branch ?? AppLocalization.text("分离 HEAD"), worktree.isPrimary ? AppLocalization.text("主目录") : URL(fileURLWithPath: worktree.path).lastPathComponent)) {
                                                    model?.selectWorktree(worktree.path, for: repository.id)
                                                }
                                            }
                                        } else {
                                            Button("切换到此组") {
                                                model?.selectProject(project.id)
                                                model?.selectWorktreeGroup(group.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
}
