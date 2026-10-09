import SwiftUI

/// A readable summary for metadata-only moves, shared by working and committed changes.
struct PatchSummaryView: View {
    let text: String

    var body: some View {
        let files = CommitPatch.parse(text).files
        if !files.isEmpty && files.allSatisfy(\.isPureRename) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 16) {
                        Label(AppLocalization.text("文件已移动或重命名，内容未变"), systemImage: "arrow.right.doc.on.clipboard")
                            .appFont(size: 14, weight: .semibold)
                        path(file.oldPath ?? "", title: "原路径")
                        path(file.path, title: "新路径")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
        } else {
            HighlightedPatchText(text: text)
        }
    }

    private func path(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLocalization.text(title)).appFont(size: 11).foregroundStyle(.secondary)
            Text(value).appFont(size: 12, design: .monospaced)
        }
    }
}
