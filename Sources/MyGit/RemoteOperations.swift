import Foundation
import SwiftUI

enum RemoteOperation: String, CaseIterable, Identifiable {
    case fetch, pull, push
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct RemoteConfiguration: Equatable {
    let branch: String
    let head: String
    let remotes: [String]
    let fetchURLs: [String: String]
    let pushURLs: [String: String]
    let upstreamRemote: String
    let upstreamBranch: String

    static func read(in path: String) throws -> Self {
        let branch = (try? CommitProcess.gitText(["symbolic-ref", "--quiet", "--short", "HEAD"], in: path)) ?? ""
        let head = (try? CommitProcess.gitText(["rev-parse", "--verify", "HEAD"], in: path)) ?? ""
        let remotes = try CommitProcess.gitText(["remote"], in: path).split(separator: "\n").map(String.init)
        var fetch: [String: String] = [:], push: [String: String] = [:]
        for remote in remotes {
            fetch[remote] = try CommitProcess.gitText(["remote", "get-url", "--all", remote], in: path)
            push[remote] = try CommitProcess.gitText(["remote", "get-url", "--push", "--all", remote], in: path)
        }
        let upstreamRemote = branch.isEmpty ? "" : (try? CommitProcess.gitText(["config", "--get", "branch.\(branch).remote"], in: path)) ?? ""
        let merge = branch.isEmpty ? "" : (try? CommitProcess.gitText(["config", "--get", "branch.\(branch).merge"], in: path)) ?? ""
        let upstreamBranch = merge.hasPrefix("refs/heads/") ? String(merge.dropFirst(11)) : ""
        return Self(branch: branch, head: head, remotes: remotes, fetchURLs: fetch, pushURLs: push,
                    upstreamRemote: upstreamRemote, upstreamBranch: upstreamBranch)
    }
}

struct RemoteRequest {
    let checkout: String
    let configuration: RemoteConfiguration
    let operation: RemoteOperation
    let remote: String
    let branch: String
    let setUpstream: Bool

    static func quick(checkout: String, configuration: RemoteConfiguration, operation: RemoteOperation) throws -> Self {
        let remote: String
        let branch: String
        if operation == .fetch {
            remote = configuration.remotes.contains(configuration.upstreamRemote) ? configuration.upstreamRemote
                : configuration.remotes.contains("origin") ? "origin"
                : configuration.remotes.count == 1 ? configuration.remotes[0] : ""
            branch = ""
        } else {
            guard configuration.remotes.contains(configuration.upstreamRemote), !configuration.upstreamBranch.isEmpty else {
                throw CommitFailure.message(AppLocalization.text("当前分支未配置远端 upstream，请从仓库右键菜单选择目标分支。"))
            }
            remote = configuration.upstreamRemote
            branch = configuration.upstreamBranch
        }
        guard !remote.isEmpty else {
            throw CommitFailure.message(AppLocalization.text("无法确定远端，请从仓库右键菜单选择远端。"))
        }
        return Self(checkout: checkout, configuration: configuration, operation: operation, remote: remote,
                    branch: branch, setUpstream: false)
    }

    func arguments() throws -> [String] {
        guard configuration.remotes.contains(remote), !remote.hasPrefix("-") else {
            throw CommitFailure.message(AppLocalization.text("请选择有效的远端。"))
        }
        switch operation {
        case .fetch: return ["fetch", "--progress", "--no-recurse-submodules", "--", remote]
        case .pull, .push:
            guard !configuration.branch.isEmpty, !configuration.head.isEmpty else {
                throw CommitFailure.message(AppLocalization.text("此操作需要有提交的本地分支。"))
            }
            _ = try CommitProcess.git(["check-ref-format", "refs/heads/" + branch], in: checkout)
            if operation == .pull {
                // Override user settings that could rebase, stash, or recurse into other repositories.
                return ["-c", "merge.autostash=false", "pull", "--ff-only", "--no-rebase", "--no-autostash",
                        "--no-recurse-submodules", "--progress", "--", remote, "refs/heads/" + branch]
            }
            // An explicit single refspec ignores push.default, configured refspecs and tag following.
            return ["-c", "remote.\(remote).mirror=false", "-c", "push.autoSetupRemote=false", "push", "--porcelain", "--progress", "--no-force",
                    "--no-follow-tags", "--recurse-submodules=no"] + (setUpstream ? ["--set-upstream"] : [])
                + ["--", remote, "HEAD:refs/heads/" + branch]
        }
    }

    func execute(progress: CommitActivitySink? = nil) throws {
        guard CheckoutOperationLock.acquire(checkout) else {
            throw CommitFailure.message(AppLocalization.text("此 checkout 正在执行其他操作。"))
        }
        defer { CheckoutOperationLock.release(checkout) }
        guard try RemoteConfiguration.read(in: checkout) == configuration else {
            throw CommitFailure.message(AppLocalization.text("分支或远端配置已变化，请关闭后重新打开。"))
        }
        let args = try arguments()
        if operation == .pull {
            guard try CommitProcess.git(["status", "--porcelain", "-z", "--untracked-files=all"], in: checkout).isEmpty else {
                throw CommitFailure.message(AppLocalization.text("Pull 前请先提交或处理未提交修改。"))
            }
            let gitDir = try CommitProcess.gitText(["rev-parse", "--absolute-git-dir"], in: checkout)
            for name in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"] {
                guard !FileManager.default.fileExists(atPath: gitDir + "/" + name) else {
                    throw CommitFailure.message(AppLocalization.text("请先完成当前合并或变基操作。"))
                }
            }
        }
        let decoder = CommitPlainOutputDecoder(progress: progress)
        defer { decoder.finish() }
        progress?(CommitActivity(operation.title, detail: "git " + args.joined(separator: " ")))
        let result = try CommitProcess.run("/usr/bin/git", ["--no-pager"] + args, in: checkout,
            environment: ["GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "Never", "SSH_ASKPASS_REQUIRE": "never"],
            timeout: 600, onOutput: { stream, data in
                // Git progress uses carriage returns instead of newline-delimited messages.
                decoder.feed(stream, Data(data.map { $0 == 13 ? 10 : $0 }))
            })
        guard result.status == 0 else {
            throw CommitFailure.message(CommitOutputText.clean(result.diagnostic + String(decoding: result.data, as: UTF8.self)))
        }
    }
}

struct RemoteOperationTarget: Identifiable {
    let id = UUID()
    let snapshot: RepositorySnapshot
    let operation: RemoteOperation
}

struct RepositoryRemoteActions: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: RepositorySnapshot
    @StateObject private var activity = CommitActivityLog()
    @State private var running = false
    @State private var result = ""
    @State private var failure: String?
    @State private var showOutput = false
    @State private var lastOperation: RemoteOperation?
    @State private var feedbackOperation: RemoteOperation?
    @State private var feedbackToken = UUID()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RemoteOperation.allCases) { operation in
                let feedback = feedbackOperation == operation
                Button {
                    if feedback { showOutput = true }
                    else { execute(operation) }
                } label: {
                    Group {
                        if feedback && running {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: feedback ? (failure == nil ? "checkmark" : "exclamationmark.triangle")
                                  : symbol(operation))
                                .foregroundStyle(feedback ? (failure == nil ? Color.green : Color.red) : tint(operation))
                                .overlay(alignment: .topTrailing) {
                                    if !feedback, operation != .fetch, let status = snapshot.remoteStatus,
                                       !status.hasRemoteUpstream || status.missing {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.system(size: 7)).foregroundStyle(.orange).offset(x: 4, y: -3)
                                    }
                                }
                        }
                    }.appFont(size: 12).frame(width: 28, height: 26)
                }
                .buttonStyle(WorkbenchHoverButtonStyle())
                .help(hint(operation))
                .accessibilityLabel(feedback ? result : operation.title)
                .disabled(!feedback && (running || model.isOperatingRemote || model.isCommitting || model.isSwitchingBranch || model.isDiscarding
                          || snapshot.selected == nil || (operation != .fetch && snapshot.selected?.branch == nil)))
                .contextMenu {
                    if lastOperation == operation {
                        Button("实时执行详情") { showOutput = true }
                    }
                }
            }
        }.fixedSize()
        .popover(isPresented: $showOutput) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: result).font(.headline)
                if let failure { Text(verbatim: failure).font(.caption).textSelection(.enabled) }
                CommitActivityView(log: activity)
            }.padding(16).frame(width: 460)
        }
        .task(id: feedbackToken) {
            guard !running, feedbackOperation != nil else { return }
            do { try await Task.sleep(for: .seconds(failure == nil ? 4 : 8)) }
            catch { return }
            feedbackOperation = nil
        }
    }

    private func symbol(_ operation: RemoteOperation) -> String {
        if operation == .fetch { return "arrow.clockwise" }
        let pending = (snapshot.remoteStatus?.pending(operation) ?? 0) > 0
        if operation == .push { return pending ? "arrow.up.circle.fill" : "arrow.up" }
        return pending ? "arrow.down.circle.fill" : "arrow.down"
    }

    private func tint(_ operation: RemoteOperation) -> Color {
        guard operation != .fetch, let status = snapshot.remoteStatus else { return .primary }
        if status.diverged { return .orange }
        return (status.pending(operation) ?? 0) > 0 ? WorkbenchStyle.accent : WorkbenchStyle.muted
    }

    private func hint(_ operation: RemoteOperation) -> String {
        let status = snapshot.remoteStatus?.help(operation) ?? AppLocalization.text("%@：本地同步状态尚未读取。", operation.title)
        return lastOperation == operation ? status + "\n" + (failure ?? result) : status
    }

    private func execute(_ operation: RemoteOperation) {
        guard let selected = snapshot.selected, !running else { return }
        running = true; failure = nil; result = operation.title + "…"
        lastOperation = operation; feedbackOperation = operation; feedbackToken = UUID()
        let progress = activity.begin(operation.title)
        let path = selected.path
        Task {
            let prepared = await Task.detached { Result { () throws -> RemoteRequest in
                let configuration = try RemoteConfiguration.read(in: path)
                guard configuration.branch == (selected.branch ?? "") else {
                    throw CommitFailure.message(AppLocalization.text("分支或远端配置已变化，请关闭后重新打开。"))
                }
                return try RemoteRequest.quick(checkout: path, configuration: configuration, operation: operation)
            } }.value
            switch prepared {
            case .success(let request): failure = await model.executeRemoteOperation(request, progress: progress)
            case .failure(let error): failure = CommitOutputText.clean(error.localizedDescription)
            }
            running = false
            result = AppLocalization.text(failure == nil ? "%@ 完成" : "%@ 失败", operation.title)
            activity.finish(result)
            feedbackToken = UUID()
        }
    }
}

struct RemoteOperationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: RemoteOperationTarget
    @State private var configuration: RemoteConfiguration?
    @State private var remote = ""
    @State private var branch = ""
    @State private var setUpstream = false
    @State private var loading = true
    @State private var executing = false
    @State private var finished = false
    @State private var failure: String?
    @StateObject private var activity = CommitActivityLog()
    private var checkout: String { target.snapshot.selected?.path ?? target.snapshot.repository.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target.operation.title + " · " + target.snapshot.repository.name).font(.title2.bold())
            Text(verbatim: checkout).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
            if loading { ProgressView() }
            if let configuration {
                Text(AppLocalization.text("当前分支：%@", configuration.branch.isEmpty ? AppLocalization.text("分离 HEAD") : configuration.branch))
                Picker("远端", selection: $remote) {
                    ForEach(configuration.remotes, id: \.self) { Text(verbatim: $0).tag($0) }
                }.disabled(executing || finished)
                Text(verbatim: CommitOutputText.clean((target.operation == .push ? configuration.pushURLs : configuration.fetchURLs)[remote] ?? ""))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if target.operation != .fetch {
                    LabeledContent("目标远端分支") {
                        TextField("目标远端分支", text: $branch).disabled(executing || finished)
                    }
                    if target.operation == .push {
                        Toggle("设置为 upstream", isOn: $setUpstream).disabled(executing || finished)
                        Text("仅推送当前分支到上面的目标分支。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Pull 仅允许 fast-forward；请先处理未提交修改。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let failure { Text(verbatim: failure).foregroundStyle(.red).textSelection(.enabled) }
            if activity.started != nil { CommitActivityView(log: activity) }
            if finished { Label("操作完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.disabled(executing)
                if !finished {
                    Button(AppLocalization.text("确认并执行 %@", target.operation.title)) { execute() }
                        .buttonStyle(.borderedProminent)
                        .disabled(loading || executing || remote.isEmpty || (target.operation != .fetch && (branch.isEmpty || configuration?.branch.isEmpty != false || configuration?.head.isEmpty != false)))
                }
            }
        }.padding(24).frame(minWidth: 620, idealWidth: 740, minHeight: 450, idealHeight: 640)
            .interactiveDismissDisabled(executing)
            .task {
                let path = checkout
                let result = await Task.detached { Result { try RemoteConfiguration.read(in: path) } }.value
                switch result {
                case .success(let value):
                    configuration = value
                    remote = value.remotes.contains(value.upstreamRemote) ? value.upstreamRemote : (value.remotes.contains("origin") ? "origin" : value.remotes.first ?? "")
                    branch = value.upstreamBranch.isEmpty ? value.branch : value.upstreamBranch
                    setUpstream = value.upstreamRemote.isEmpty
                    if value.remotes.isEmpty { failure = AppLocalization.text("此仓库尚未配置远端。") }
                case .failure(let error): failure = CommitOutputText.clean(error.localizedDescription)
                }
                loading = false
            }
    }

    private func execute() {
        guard let configuration else { return }
        let request = RemoteRequest(checkout: checkout, configuration: configuration, operation: target.operation,
                                    remote: remote, branch: branch, setUpstream: setUpstream)
        executing = true; failure = nil
        let progress = activity.begin(target.operation.title)
        Task {
            failure = await model.executeRemoteOperation(request, progress: progress)
            executing = false; finished = failure == nil
            activity.finish(finished ? AppLocalization.text("操作完成") : AppLocalization.text("操作失败"))
        }
    }
}
