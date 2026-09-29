import SwiftUI

@main struct MyGitApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("工作树") {
                Button("快速切换…") { model.showQuickSwitch = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("刷新") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(model.projects) { project in
                    Menu(project.name) {
                        ForEach(project.worktreeGroups) { group in
                            Menu(group.name) {
                                Button("切换整组") {
                                    model.selectProject(project.id)
                                    model.selectWorktreeGroup(group.id)
                                }
                                ForEach(project.repositories) { repository in
                                    Menu(repository.name) {
                                        if model.selectedProjectID == project.id,
                                           model.selectedWorktreeGroupID == group.id,
                                           let snapshot = model.snapshots.first(where: { $0.repository.id == repository.id }) {
                                            Button("自动匹配") { model.selectWorktree(nil, for: repository.id) }
                                            ForEach(snapshot.worktrees) { worktree in
                                                Button("\(worktree.branch ?? "分离 HEAD") · \(worktree.isPrimary ? "主目录" : URL(fileURLWithPath: worktree.path).lastPathComponent)") {
                                                    model.selectWorktree(worktree.path, for: repository.id)
                                                }
                                            }
                                        } else {
                                            Button("切换到此组") {
                                                model.selectProject(project.id)
                                                model.selectWorktreeGroup(group.id)
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
}
