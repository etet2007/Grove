import SwiftUI

enum BranchPickerOptions {
    static func isToolStash(_ name: String) -> Bool {
        name.range(of: "^ugit-stash/[0-9a-fA-F]{7,40}-[13]$", options: .regularExpression) != nil
    }

    static func visibleBranches(_ branches: [LocalBranch], current: String?, query: String, showToolStashes: Bool) -> [LocalBranch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return branches.filter {
            (showToolStashes || !isToolStash($0.name) || $0.name == current)
                && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))
        }.sorted {
            if ($0.name == current) != ($1.name == current) { return $0.name == current }
            return $0.name < $1.name
        }
    }
}

struct BranchPicker: View {
    @EnvironmentObject private var model: AppModel
    let repositoryID: UUID
    let worktree: Worktree
    @State private var isPresented = false
    @State private var branches: [LocalBranch] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var query = ""
    @State private var showToolStashes = false

    private var visibleBranches: [LocalBranch] {
        BranchPickerOptions.visibleBranches(branches, current: worktree.branch, query: query, showToolStashes: showToolStashes)
    }
    private var toolStashCount: Int {
        branches.filter { BranchPickerOptions.isToolStash($0.name) && $0.name != worktree.branch }.count
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 4) {
                Text(worktree.branch ?? AppLocalization.text("分离 HEAD"))
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").appFont(size: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkbenchHoverButtonStyle())
        .disabled(model.isSwitchingBranch || model.isDiscarding)
        .help(AppLocalization.text("切换本地分支"))
        .accessibilityLabel(AppLocalization.text("切换本地分支：%@", worktree.branch ?? AppLocalization.text("分离 HEAD")))
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本地分支").appFont(size: 12, weight: .semibold)
                    TextField("搜索本地分支", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("搜索本地分支")
                        .workbenchHoverFeedback()
                    if toolStashCount > 0 {
                        Toggle(isOn: $showToolStashes) {
                            Text(AppLocalization.text("显示工具临时分支（%ld）", toolStashCount))
                        }
                        .toggleStyle(.checkbox)
                        .appFont(size: 10)
                        .workbenchHoverFeedback()
                    }
                }
                .padding(12)
                Divider()
                PickerScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if isLoading {
                            ProgressView().controlSize(.small).padding(8)
                        } else if let loadError {
                            Text(loadError).foregroundStyle(.red).padding(8)
                        } else if visibleBranches.isEmpty {
                            Text(AppLocalization.text(branches.isEmpty ? "暂无本地分支" : "没有匹配的分支")).foregroundStyle(.secondary).padding(8)
                        } else {
                            ForEach(visibleBranches) { branch in
                                let current = branch.name == worktree.branch
                                let occupied = branch.checkoutPath.map { $0 != worktree.path } ?? false
                                Button {
                                    isPresented = false
                                    Task { await model.switchBranch(branch.name, for: repositoryID, checkoutPath: worktree.path) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: current ? "checkmark" : "arrow.triangle.branch")
                                            .frame(width: 14)
                                        Text(branch.name).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 4)
                                        if occupied { Text("其他工作树使用中").foregroundStyle(.secondary) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8).contentShape(Rectangle())
                                }
                                .buttonStyle(WorkbenchButtonStyle())
                                .disabled(current || occupied || model.isSwitchingBranch)
                                .help(branch.checkoutPath ?? branch.name)
                            }
                        }
                    }
                    .appFont(size: 11).padding(8)
                }
                .id(query)
                .id(showToolStashes)
            }
            .frame(width: 360)
            .foregroundStyle(Color.primary)
            .background(WorkbenchStyle.sidebar)
            .preferredColorScheme(.dark)
            .task {
                isLoading = true
                loadError = nil
                query = ""
                showToolStashes = false
                do {
                    let path = worktree.path
                    branches = try await Task.detached(priority: .userInitiated) { try GitClient.localBranches(in: path) }.value
                } catch { loadError = error.localizedDescription }
                isLoading = false
            }
        }
    }
}
