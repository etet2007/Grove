import SwiftUI

struct CommitDetailView: View {
    let patch: CommitPatch
    let layout: DetailLayout
    let checkoutPath: String?
    var commitHash: String? = nil
    @State private var selectedIndex = 0
    @State private var showAll = false
    @State private var sources: [Int: [MergeSourceCommit]] = [:]
    @State private var sourceFailures = Set<Int>()

    private var selected: CommitFilePatch { patch.files[min(selectedIndex, patch.files.count - 1)] }
    private var scrollID: String { showAll ? "all" : "file:\(selected.id)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(AppLocalization.text("%ld files", patch.files.count)).fontWeight(.semibold)
                counts(additions: patch.additions, deletions: patch.deletions)
                Spacer()
                Button(AppLocalization.text(showAll ? "Return to Single File" : "Show All")) { showAll.toggle() }
                    .buttonStyle(WorkbenchButtonStyle())
            }
            .appFont(size: 12)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if patch.isMerge {
                Text(AppLocalization.text("合并提交 · 相对第一父提交的修改"))
                    .appFont(size: 11).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(patch.files) { file in
                            Button {
                                selectedIndex = file.id
                                showAll = false
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(AppLocalization.text(file.change.badge))
                                        .appFont(size: 11, weight: .bold, design: .monospaced)
                                        .foregroundStyle(changeColor(file.change))
                                        .frame(width: 22, height: 22)
                                        .background(changeColor(file.change).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.name).appFont(size: 12, weight: .semibold)
                                            .lineLimit(1).truncationMode(.middle)
                                        Text(file.directory.isEmpty ? AppLocalization.text("仓库根目录") : file.directory)
                                            .appFont(size: 10).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                        if let commits = sources[file.id], !commits.isEmpty {
                                            Text(AppLocalization.text("合入相关作者：%@", commits.authorSummary))
                                                .appFont(size: 10).foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if file.isBinary {
                                        Text(AppLocalization.text("二进制")).appFont(size: 11).foregroundStyle(.secondary)
                                    } else { counts(additions: file.additions, deletions: file.deletions) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .background(!showAll && selected.id == file.id ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help(file.path)
                            .finderContextMenu(path: localPath(file.path))
                            .id(file.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(180, CGFloat(patch.files.count) * (patch.isMerge ? 64 : 48) + 4))
                .onChange(of: selectedIndex) { _, value in proxy.scrollTo(value) }
            }
            Divider()
            if !showAll {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.path).appFont(size: 12, weight: .semibold)
                            .lineLimit(1).truncationMode(.middle).help(selected.path)
                            .finderContextMenu(path: localPath(selected.path))
                        Text(fileDescription).appFont(size: 11).foregroundStyle(.secondary)
                            .lineLimit(1).help(fileDescription)
                    }
                    Spacer(minLength: 0)
                    Text("\(selectedIndex + 1) / \(patch.files.count)")
                        .appFont(size: 11).foregroundStyle(.secondary)
                    Button { selectedIndex -= 1 } label: { Image(systemName: "chevron.up") }
                        .disabled(selectedIndex == 0).help(AppLocalization.text("上一个文件"))
                    Button { selectedIndex += 1 } label: { Image(systemName: "chevron.down") }
                        .disabled(selectedIndex == patch.files.count - 1).help(AppLocalization.text("下一个文件"))
                }
                .buttonStyle(WorkbenchButtonStyle())
                .padding(12)
                if patch.isMerge {
                    MergeFileSourcesView(commits: sources[selected.id], failed: sourceFailures.contains(selected.id))
                        .id(selected.id)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
                Divider()
            }
            let diff = showAll ? patch.fullDiff : selected.diff
            if layout == .split && diff.hasChanges {
                SplitDiffView(diff: diff, oldTitle: patch.isMerge ? "第一父提交" : "父提交", newTitle: "提交后", resetID: scrollID,
                              singleSide: showAll ? nil : singleSide)
                    .id(scrollID)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    PatchSummaryView(text: showAll ? patch.files.map(\.patch).joined(separator: "\n") : selected.patch)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                }
                .id(scrollID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selected.id) {
            guard patch.isMerge, sources[selected.id] == nil else { return }
            guard let commitHash, let checkoutPath else {
                sourceFailures.insert(selected.id)
                return
            }
            let file = selected
            let session = GitReadSession()
            await withTaskCancellationHandler {
                let task = Task.detached(priority: .utility) {
                    try GitClient.$readSession.withValue(session) {
                        try GitClient.mergeSources(commit: commitHash, file: file, in: checkoutPath)
                    }
                }
                do {
                    let result = try await task.value
                    guard !Task.isCancelled else { return }
                    sources[file.id] = result
                    sourceFailures.remove(file.id)
                } catch {
                    guard !Task.isCancelled else { return }
                    sourceFailures.insert(file.id)
                }
            } onCancel: {
                session.cancel()
            }
        }
    }

    private var singleSide: DiffSide? {
        switch selected.change {
        case .added: .new
        case .deleted: .old
        default: nil
        }
    }

    private func localPath(_ path: String) -> String? {
        checkoutPath.map { URL(fileURLWithPath: $0).appendingPathComponent(path).path }
    }

    private var fileDescription: String {
        let change = AppLocalization.text(selected.change.rawValue)
        if let oldPath = selected.oldPath { return AppLocalization.text("%@ from %@", change, oldPath) }
        if selected.isBinary { return AppLocalization.text("%@ · Binary file", change) }
        switch selected.change {
        case .deleted: return AppLocalization.text("File deleted · %ld lines", selected.deletions)
        case .added: return AppLocalization.text("New file · %ld lines", selected.additions)
        default: return AppLocalization.text("%@ · +%ld / −%ld", change, selected.additions, selected.deletions)
        }
    }

    private func counts(additions: Int, deletions: Int) -> some View {
        HStack(spacing: 6) {
            Text("+\(additions)").foregroundStyle(.green)
            Text("−\(deletions)").foregroundStyle(.red)
        }
        .appFont(size: 11, weight: .medium, design: .monospaced)
    }

    private func changeColor(_ change: CommitFilePatch.Change) -> Color {
        switch change {
        case .added: .green
        case .deleted: .red
        case .modified: .orange
        case .renamed, .copied: .cyan
        }
    }
}
