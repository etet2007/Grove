import SwiftUI

struct BranchPicker: View {
    @EnvironmentObject private var model: AppModel
    let repositoryID: UUID
    let worktree: Worktree
    @State private var isPresented = false
    @State private var branches: [LocalBranch] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 4) {
                Text(worktree.branch ?? AppLocalization.text("分离 HEAD"))
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").appFont(size: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isSwitchingBranch || model.isDiscarding)
        .help(AppLocalization.text("切换本地分支"))
        .accessibilityLabel(AppLocalization.text("切换本地分支：%@", worktree.branch ?? AppLocalization.text("分离 HEAD")))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地分支").appFont(size: 12, weight: .semibold).padding(8)
                    if isLoading {
                        ProgressView().controlSize(.small).padding(8)
                    } else if let loadError {
                        Text(loadError).foregroundStyle(.red).padding(8)
                    } else if branches.isEmpty {
                        Text("暂无本地分支").foregroundStyle(.secondary).padding(8)
                    } else {
                        ForEach(branches) { branch in
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
            .frame(width: 360).fixedSize(horizontal: false, vertical: true).frame(maxHeight: 360)
            .preferredColorScheme(.dark)
            .task {
                isLoading = true
                loadError = nil
                do {
                    let path = worktree.path
                    branches = try await Task.detached(priority: .userInitiated) { try GitClient.localBranches(in: path) }.value
                } catch { loadError = error.localizedDescription }
                isLoading = false
            }
        }
    }
}
