import SwiftUI

struct CommitDetailView: View {
    let patch: CommitPatch
    let layout: DetailLayout
    @State private var selectedIndex = 0
    @State private var showAll = false

    private var selected: CommitFilePatch { patch.files[min(selectedIndex, patch.files.count - 1)] }
    private var scrollID: String { showAll ? "all" : "file:\(selected.id)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(AppLocalization.text("%ld files", patch.files.count)).fontWeight(.semibold)
                counts(additions: patch.additions, deletions: patch.deletions)
                Spacer()
                Button(AppLocalization.text(showAll ? "Return to Single File" : "Show All")) { showAll.toggle() }
                    .buttonStyle(.borderless)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(changeColor(file.change))
                                        .frame(width: 22, height: 22)
                                        .background(changeColor(file.change).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.name).font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1).truncationMode(.middle)
                                        Text(file.directory.isEmpty ? AppLocalization.text("仓库根目录") : file.directory)
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 4)
                                    if file.isBinary {
                                        Text(AppLocalization.text("二进制")).font(.system(size: 11)).foregroundStyle(.secondary)
                                    } else { counts(additions: file.additions, deletions: file.deletions) }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .background(!showAll && selected.id == file.id ? Color.accentColor.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .help(file.path)
                            .id(file.id)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(180, CGFloat(patch.files.count) * 48 + 4))
                .onChange(of: selectedIndex) { _, value in proxy.scrollTo(value) }
            }
            Divider()
            if !showAll {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.path).font(.system(size: 12, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle).help(selected.path)
                        Text(fileDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).help(fileDescription)
                    }
                    Spacer(minLength: 0)
                    Text("\(selectedIndex + 1) / \(patch.files.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { selectedIndex -= 1 } label: { Image(systemName: "chevron.up") }
                        .disabled(selectedIndex == 0).help(AppLocalization.text("上一个文件"))
                    Button { selectedIndex += 1 } label: { Image(systemName: "chevron.down") }
                        .disabled(selectedIndex == patch.files.count - 1).help(AppLocalization.text("下一个文件"))
                }
                .buttonStyle(.borderless)
                .padding(12)
                Divider()
            }
            let diff = showAll ? patch.fullDiff : selected.diff
            if layout == .split && diff.hasChanges {
                SplitDiffView(diff: diff, oldTitle: "父提交", newTitle: "提交后", resetID: scrollID,
                              singleSide: showAll ? nil : singleSide)
                    .id(scrollID)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    Text(showAll ? patch.files.map(\.patch).joined(separator: "\n") : selected.patch)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                }
                .id(scrollID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var singleSide: DiffSide? {
        switch selected.change {
        case .added: .new
        case .deleted: .old
        default: nil
        }
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
        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
