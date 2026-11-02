import SwiftUI

struct UpdateSettingsView: View {
    @AppStorage(AppUpdater.repositoryKey) private var repository = ""
    @AppStorage(AppUpdater.branchKey) private var branch = "main"
    @ObservedObject private var updater = AppUpdater.shared
    @State private var confirmInstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(title: "应用更新", subtitle: "从你指定的 Git 仓库读取已发布的 Grove。")
                SettingsCard(title: "更新来源") {
                    Text(verbatim: "Grove \(AppUpdater.currentVersion) (\(AppUpdater.currentBuild))")
                        .appFont(size: 13, weight: .medium)
                    Text("Git 仓库地址").appFont(size: 12)
                    WorkbenchTextField(title: "HTTPS 或 SSH 仓库地址", text: $repository)
                    Text("发布分支").appFont(size: 12)
                    WorkbenchTextField(title: "发布分支", text: $branch)
                    Text("仓库根目录需包含 latest.json 和 MyGit.zip。仅手动检查；SSH 和 HTTPS 使用本机 Git 认证。")
                        .appFont(size: 12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("检查更新") { updater.check(repository: repository, branch: branch) }
                        .disabled(repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || branch.isEmpty)
                }
                .disabled(updater.busy)
                if updater.busy || !updater.message.isEmpty {
                    HStack(spacing: 10) {
                        if updater.busy { ProgressView().controlSize(.small) }
                        Text(verbatim: updater.message).appFont(size: 12).textSelection(.enabled)
                    }
                }
                if let update = updater.available {
                    SettingsCard(title: "可用更新") {
                        Text(verbatim: "Grove \(update.manifest.version) (\(update.manifest.build))")
                            .appFont(size: 16, weight: .semibold)
                        if !update.manifest.notes.isEmpty {
                            Text(verbatim: update.manifest.notes).appFont(size: 12).textSelection(.enabled)
                        }
                        Text("确认后退出并替换当前应用，然后重新启动。工程配置会保留。")
                            .appFont(size: 12).foregroundStyle(.secondary)
                        Button("更新并重启…") { confirmInstall = true }
                            .buttonStyle(WorkbenchButtonStyle(emphasized: true)).disabled(updater.busy)
                    }
                }
            }
            .padding(32).frame(maxWidth: 820).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(WorkbenchButtonStyle())
        .onChange(of: repository) { _, _ in if !updater.busy { updater.clear() } }
        .onChange(of: branch) { _, _ in if !updater.busy { updater.clear() } }
        .alert("更新并重启 Grove？", isPresented: $confirmInstall) {
            Button("取消", role: .cancel) {}
            Button("更新并重启") { updater.install() }
        } message: { Text("应用将退出并安装已校验的新版，工程配置会保留。") }
    }
}
