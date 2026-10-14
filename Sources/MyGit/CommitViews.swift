import SwiftUI
import AppKit

struct CommitSettingsView: View {
    @AppStorage(CommitPreferences.agentKey) private var kind = "codex"
    @AppStorage(CommitPreferences.executableKey) private var executable = ""
    @AppStorage(CommitPreferences.skillKey) private var skill = ""
    @AppStorage(CommitPreferences.modelKey) private var agentModel = ""
    @State private var agents: [DetectedCommitAgent] = []
    @State private var detecting = false
    @State private var testing = false
    @State private var feedback = ""
    @State private var testTask: Task<Void, Never>?
    @State private var worker: Task<String, Error>?
    @StateObject private var activity = CommitActivityLog()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(title: "提交", subtitle: "选择你的 Agent 和 Skill，生成可审阅的提交方案。")
                SettingsCard(title: "默认 Agent") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(CommitAgentKind.allCases) { value in
                            agentChoice(value)
                        }
                    }
                    HStack {
                        if detecting { ProgressView().controlSize(.small); Text("正在检测…") }
                        else { Text("自动检测本机安装，沿用已有登录配置。") }
                        Spacer()
                        Button("重新检测") { detect() }.disabled(detecting || testing)
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    DisclosureGroup("路径与模型") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("可执行文件路径", text: $executable)
                                    .textFieldStyle(.roundedBorder)
                                Button("选择…") { if let path = chooseFile() { executable = path } }
                            }
                            TextField("模型（留空沿用 Agent 默认配置）", text: $agentModel)
                                .textFieldStyle(.roundedBorder)
                        }.padding(.top, 10)
                    }
                    .font(.system(size: 12))
                }
                SettingsCard(title: "提交 Skill") {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 22)).foregroundStyle(WorkbenchStyle.accent)
                            .frame(width: 44, height: 44)
                            .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: skill.isEmpty ? AppLocalization.text("尚未选择 Skill") : URL(fileURLWithPath: skill).deletingLastPathComponent().lastPathComponent)
                                .font(.system(size: 14, weight: .medium))
                            if !skill.isEmpty {
                                Text(verbatim: skill).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            } else {
                                Text("选择一次，之后准备提交时自动加载。")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(AppLocalization.text(skill.isEmpty ? "选择 Skill…" : "更换…")) {
                            if let path = chooseFile(markdown: true) { skill = path; feedback = "" }
                        }
                    }
                    if let detected = detectedSkill, skill != detected {
                        HStack {
                            Image(systemName: "sparkle").foregroundStyle(WorkbenchStyle.accent)
                            Text("已找到本机 commit-message")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button("使用此 Skill") { skill = detected; feedback = "" }
                                .buttonStyle(WorkbenchButtonStyle(emphasized: true))
                        }
                        .padding(12).background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("自动加载 Skill 及引用的本地规范文件。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("验证配置").font(.system(size: 13, weight: .medium))
                        Text("使用示例改动生成建议，不会创建提交。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if testing {
                        ProgressView().controlSize(.small)
                        Button("取消") { worker?.cancel() }
                    }
                    Button("测试生成") { testGeneration() }
                        .disabled(testing || executable.isEmpty || skill.isEmpty)
                }
                if activity.started != nil { CommitActivityView(log: activity) }
                if !feedback.isEmpty {
                    Text(verbatim: feedback).font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkbenchStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("Agent 沿用本机登录与模型配置；分析内容可能由其模型服务处理。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 820).padding(32).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(WorkbenchButtonStyle())
        .onChange(of: kind) { _, value in
            executable = agents.first { $0.kind.rawValue == value && $0.failure == nil }?.path ?? ""
            agentModel = ""; feedback = ""
        }
        .task { detect() }
        .onDisappear { worker?.cancel(); testTask?.cancel() }
    }

    private func agentChoice(_ value: CommitAgentKind) -> some View {
        let selected = kind == value.rawValue
        let installed = agents.first { $0.kind == value }
        return Button { kind = value.rawValue } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "terminal").font(.system(size: 18))
                        .foregroundStyle(selected ? WorkbenchStyle.accent : .secondary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                }
                Text(verbatim: value.title).font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(installed?.failure == nil && installed != nil ? Color.green : WorkbenchStyle.muted)
                        .frame(width: 5, height: 5)
                    Text(AppLocalization.text(installed == nil ? "未检测到" : installed?.failure == nil ? "已安装" : "无法调用"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let installed {
                    Text(verbatim: installed.version).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(selected ? WorkbenchStyle.accent.opacity(0.06) : WorkbenchStyle.background,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? WorkbenchStyle.accent.opacity(0.65) : WorkbenchStyle.border))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(WorkbenchHoverButtonStyle())
        .disabled(testing)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func chooseFile(markdown: Bool = false) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if markdown { panel.allowedContentTypes = [.plainText]; panel.allowsOtherFileTypes = true }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private var detectedSkill: String? {
        ["/.codex/skills/commit-message/SKILL.md", "/.agents/skills/commit-message/SKILL.md",
         "/.claude/skills/commit-message/SKILL.md", "/.omp/agent/skills/commit-message/SKILL.md"]
            .map { NSHomeDirectory() + $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func detect() {
        guard !detecting else { return }
        detecting = true
        Task {
            let found = await Task.detached { AgentDiscovery.detect() }.value
            agents = found; detecting = false
            if executable.isEmpty {
                let available = found.filter { $0.failure == nil }
                if available.count == 1, let first = available.first {
                    kind = first.kind.rawValue; executable = first.path
                } else if let current = available.first(where: { $0.kind.rawValue == kind }) { executable = current.path }
            }
        }
    }

    private func testGeneration() {
        let preferences = CommitPreferences()
        let progress = activity.begin("准备测试生成")
        testing = true; feedback = ""
        let work = Task.detached { () throws -> String in
            _ = try CommitSkill.fileURL(path: preferences.skillPath)
            let inspection = AgentDiscovery.inspect(kind: preferences.kind, path: preferences.executable)
            if let failure = inspection.failure { throw CommitFailure.message(failure) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyGitSkillTest-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try CommitProcess.git(["init", "-b", "main"], in: root.path)
            try Data("# Example\n\nDocument how to launch the app.\n".utf8).write(to: root.appendingPathComponent("README.md"))
            let snapshot = try CommitSnapshot.capture(checkout: root.path, scope: .all, progress: progress)
            let plan = try CommitAgentClient.generate(snapshot: snapshot, preferences: preferences,
                                                     intent: "Add first-use documentation. This is a settings test; generate suggestions only.", progress: progress)
            return plan.commits.map(\.message).joined(separator: "\n\n")
        }
        worker = work
        testTask = Task {
            do { feedback = try await work.value; activity.finish("生成完成") }
            catch is CancellationError { feedback = AppLocalization.text("已取消。"); activity.finish("已取消。") }
            catch { feedback = error.localizedDescription; activity.finish("生成失败") }
            testing = false; worker = nil
        }
    }
}

@MainActor final class CommitPreparation: ObservableObject {
    let activity = CommitActivityLog()
    @Published var scope: CommitScope
    @Published var intent = ""
    @Published var snapshot: CommitSnapshot?
    @Published var plan: CommitPlan?
    @Published var selectedID: String?
    @Published var generating = false
    @Published var failure: String?
    @Published var result: CommitExecutionResult?
    @Published var usedPreferences: CommitPreferences?
    private var worker: Task<(CommitSnapshot, CommitPlan), Error>?
    let target: RepositorySnapshot

    init(target: RepositorySnapshot) {
        self.target = target
        scope = target.files.contains(where: \.hasStaged) ? .staged : .all
    }

    func generate() {
        guard !generating, let checkout = target.selected?.path else { return }
        let preferences = CommitPreferences(), scope = scope, intent = intent
        let progress = activity.begin("读取仓库修改")
        usedPreferences = preferences
        generating = true; failure = nil; snapshot = nil; plan = nil; result = nil
        let work = Task.detached {
            let snapshot = try CommitSnapshot.capture(checkout: checkout, scope: scope, progress: progress)
            let plan = try CommitAgentClient.generate(snapshot: snapshot, preferences: preferences, intent: intent, progress: progress)
            return (snapshot, plan)
        }
        worker = work
        Task {
            do {
                let value = try await work.value
                snapshot = value.0; plan = value.1; selectedID = value.1.commits.first?.id
                activity.finish("生成完成")
            } catch is CancellationError { failure = AppLocalization.text("已取消。"); activity.finish("已取消。") }
            catch { failure = error.localizedDescription; activity.finish("生成失败") }
            generating = false; worker = nil
        }
    }

    func cancel() { worker?.cancel() }

    func omit(_ path: String) {
        guard var value = plan else { return }
        for index in value.commits.indices { value.commits[index].paths.removeAll { $0 == path } }
        value.commits.removeAll { $0.paths.isEmpty }
        if !value.omitted.contains(path) { value.omitted.append(path) }
        plan = value
        if !value.commits.contains(where: { $0.id == selectedID }) { selectedID = value.commits.first?.id }
    }

    func move(_ path: String, to id: String) {
        guard var value = plan else { return }
        for index in value.commits.indices { value.commits[index].paths.removeAll { $0 == path } }
        value.omitted.removeAll { $0 == path }
        if let index = value.commits.firstIndex(where: { $0.id == id }) { value.commits[index].paths.append(path) }
        value.commits.removeAll { $0.paths.isEmpty }
        plan = value; selectedID = id
    }

    func merge() {
        guard var value = plan, value.commits.count > 1 else { return }
        value.commits[0].paths = value.commits.flatMap(\.paths)
        value.commits = [value.commits[0]]
        plan = value; selectedID = value.commits[0].id
    }
}

struct CommitReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preparation: CommitPreparation
    @State private var executing = false
    @State private var confirm = false

    init(target: RepositorySnapshot) { _preparation = StateObject(wrappedValue: CommitPreparation(target: target)) }

    private var frozen: Bool { preparation.generating || executing || preparation.result != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: preparation.target.repository.name).font(.headline)
                    Text(verbatim: preparation.target.selected?.branch ?? AppLocalization.text("分离 HEAD"))
                    Text(verbatim: preparation.target.selected?.path ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if preparation.target.isFallback { Text("共享主目录").foregroundStyle(.orange) }
                }
                Spacer()
                Button("设置…") { SettingsWindowController.shared.show() }.disabled(executing)
            }
            HStack {
                let preferences = preparation.usedPreferences ?? CommitPreferences()
                Text(verbatim: preferences.kind.title + " · " + (preferences.skillPath.isEmpty ? AppLocalization.text("尚未选择 Skill") : URL(fileURLWithPath: preferences.skillPath).deletingLastPathComponent().lastPathComponent))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("范围", selection: $preparation.scope) {
                    ForEach(CommitScope.allCases) { Text(AppLocalization.text($0.rawValue)).tag($0) }
                }
                .frame(width: 180).disabled(frozen)
                .onChange(of: preparation.scope) { _, _ in preparation.plan = nil; preparation.snapshot = nil }
            }
            TextField("本次修改的目的，或对拆分方案的反馈（可选）", text: $preparation.intent).disabled(frozen)
            HStack {
                Button(preparation.plan == nil ? "生成提交方案" : "重新生成") { preparation.generate() }.disabled(frozen)
                if preparation.generating { ProgressView().controlSize(.small); Button("取消生成") { preparation.cancel() } }
                Text("按完整文件拆分；确认前不会暂存或提交。")
                    .foregroundStyle(.secondary).font(.caption)
            }
            if let failure = preparation.failure { Text(verbatim: failure).foregroundStyle(.red).textSelection(.enabled) }
            if preparation.activity.started != nil { CommitActivityView(log: preparation.activity) }
            if let plan = preparation.plan, let snapshot = preparation.snapshot {
                HSplitView {
                    VStack(alignment: .leading) {
                        List(selection: $preparation.selectedID) {
                            ForEach(plan.commits) { commit in
                                VStack(alignment: .leading) {
                                    Text(verbatim: commit.message.components(separatedBy: "\n").first ?? "")
                                    Text(AppLocalization.text("%ld files", commit.paths.count)).font(.caption).foregroundStyle(.secondary)
                                }.tag(commit.id)
                            }
                        }
                        Button("合并为一笔") { preparation.merge() }.disabled(frozen || plan.commits.count < 2)
                        if !plan.omitted.isEmpty {
                            Text("保留未提交").font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                ForEach(plan.omitted, id: \.self) { path in
                                    HStack {
                                        Text(verbatim: path).font(.caption)
                                        Spacer()
                                        Menu("加入") {
                                            ForEach(plan.commits) { commit in
                                                Button(commit.message.components(separatedBy: "\n")[0]) { preparation.move(path, to: commit.id) }
                                            }
                                        }.disabled(frozen)
                                    }
                                }
                            }.frame(maxHeight: 100)
                        }
                    }.frame(minWidth: 220, idealWidth: 250)
                    VStack(alignment: .leading) {
                        if let index = plan.commits.firstIndex(where: { $0.id == preparation.selectedID }) {
                            let commit = plan.commits[index]
                            TextEditor(text: Binding(get: { preparation.plan?.commits.first { $0.id == commit.id }?.message ?? "" },
                                                     set: { value in
                                if let i = preparation.plan?.commits.firstIndex(where: { $0.id == commit.id }) { preparation.plan?.commits[i].message = value }
                            }))
                            .font(.system(.body, design: .monospaced)).frame(height: 85).disabled(frozen)
                            Text(verbatim: commit.reason).font(.caption).foregroundStyle(.secondary)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(commit.paths, id: \.self) { path in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(verbatim: path).font(.headline).textSelection(.enabled)
                                                Spacer()
                                                Menu("移动到") {
                                                    ForEach(plan.commits.filter { $0.id != commit.id }) { destination in
                                                        Button(destination.message.components(separatedBy: "\n")[0]) { preparation.move(path, to: destination.id) }
                                                    }
                                                    Button("保留未提交") { preparation.omit(path) }
                                                }.disabled(frozen)
                                            }
                                            Text(verbatim: snapshot.files.first { $0.path == path }?.patch ?? "")
                                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }.frame(minWidth: 430)
                }
            } else { Spacer(); Text("生成后可审阅每笔提交的说明、文件和 diff。").foregroundStyle(.secondary); Spacer() }
            if let result = preparation.result {
                Text(AppLocalization.text("已完成 %ld 笔提交", result.hashes.count)).foregroundStyle(result.failure == nil ? .green : .orange)
                ForEach(result.hashes, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()).textSelection(.enabled) }
                if let failure = result.failure { Text(verbatim: failure).foregroundStyle(.red).textSelection(.enabled) }
                if result.failure != nil {
                    Text("已停止后续操作，已完成的提交保留。请检查仓库后重新准备。").font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("关闭") { preparation.cancel(); dismiss() }.disabled(executing)
                if executing { ProgressView().controlSize(.small) }
                Button(AppLocalization.text("确认并提交 %ld 笔", preparation.plan?.commits.count ?? 0)) { confirm = true }
                    .buttonStyle(WorkbenchButtonStyle(emphasized: true))
                    .disabled(frozen || preparation.plan?.commits.isEmpty != false)
            }
        }
        .padding(20).frame(width: 950, height: 720)
        .background(WorkbenchStyle.background).preferredColorScheme(.dark)
        .buttonStyle(WorkbenchButtonStyle())
        .interactiveDismissDisabled(executing)
        .onDisappear { preparation.cancel() }
        .confirmationDialog("提交当前审阅的方案？", isPresented: $confirm) {
            Button("确认提交") { execute() }
            Button("取消", role: .cancel) { }
        } message: { Text("将按显示的顺序创建本地提交。Git hook 或签名失败时停止后续提交。") }
    }

    private func execute() {
        guard let snapshot = preparation.snapshot, let plan = preparation.plan, !executing else { return }
        executing = true
        let progress = preparation.activity.begin("开始提交")
        Task {
            let result = await model.executeCommitPlan(plan, snapshot: snapshot, progress: progress)
            preparation.result = result
            preparation.activity.finish(result.failure == nil ? "提交完成" : "提交已停止")
            executing = false
        }
    }
}
