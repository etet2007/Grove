import SwiftUI

/// Readable summaries alongside text patches, shared by working and committed changes.
struct PatchSummaryView: View {
    let text: String

    var body: some View {
        let files = CommitPatch.parse(text, prepareDiff: false).files
        if files.contains(where: { $0.summaryTitle != nil }) {
            VStack(alignment: .leading, spacing: 24) {
                let preamble = text.components(separatedBy: "\n").prefix { !$0.hasPrefix("diff --git ") }.joined(separator: "\n")
                if !preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HighlightedPatchText(text: preamble)
                }
                ForEach(files) { file in
                    if let title = file.summaryTitle {
                        summary(file, title: title)
                    } else {
                        HighlightedPatchText(text: PatchPresentation.readableText(file.patch))
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            HighlightedPatchText(text: PatchPresentation.readableText(text))
        }
    }

    private func summary(_ file: CommitFilePatch, title: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(AppLocalization.text(title), systemImage: file.isPureRename ? "arrow.right.doc.on.clipboard" : "doc")
                .appFont(size: 14, weight: .semibold)
            if let oldPath = file.oldPath {
                path(oldPath, title: "原路径")
                path(file.path, title: "新路径")
            } else {
                path(file.path, title: "文件路径")
            }
            if file.isBinary && !file.isPureRename {
                Text(AppLocalization.text("二进制文件无法显示文本差异。"))
                    .appFont(size: 12).foregroundStyle(.secondary)
            }
            ForEach(Array(file.summaryVersions.enumerated()), id: \.offset) { _, version in
                path(version.1, title: version.0)
            }
            if let mode = file.modeChangeDescription {
                Text(AppLocalization.text(mode)).appFont(size: 12).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func path(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppLocalization.text(title)).appFont(size: 11).foregroundStyle(.secondary)
            Text(value).appFont(size: 12, design: .monospaced)
        }
    }
}
