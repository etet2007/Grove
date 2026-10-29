import SwiftUI

struct PreparedPatchSummary {
    struct Summary {
        let title: String
        let path: String
        let oldPath: String?
        let isPureRename: Bool
        let isBinary: Bool
        let versions: [(String, String)]
        let mode: String?
    }
    enum Section {
        case text(String)
        case summary(Summary)
    }
    let sections: [Section]

    static func prepare(_ text: String) -> PreparedPatchSummary? {
        let files = CommitPatch.parse(text, prepareDiff: false).files
        guard !Task.isCancelled else { return nil }
        let titles = files.map { $0.summaryTitle }
        guard !Task.isCancelled else { return nil }
        guard titles.contains(where: { $0 != nil }) else {
            let readable = PatchPresentation.readableText(text)
            return Task.isCancelled ? nil : PreparedPatchSummary(sections: [.text(readable)])
        }
        var sections: [Section] = []
        let preamble = text.components(separatedBy: "\n").prefix { !$0.hasPrefix("diff --git ") }.joined(separator: "\n")
        if !preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sections.append(.text(preamble)) }
        for (file, title) in zip(files, titles) {
            guard !Task.isCancelled else { return nil }
            if let title {
                sections.append(.summary(Summary(title: title, path: file.path, oldPath: file.oldPath,
                    isPureRename: file.isPureRename, isBinary: file.isBinary,
                    versions: file.summaryVersions, mode: file.modeChangeDescription)))
            } else {
                sections.append(.text(PatchPresentation.readableText(file.patch)))
            }
        }
        return Task.isCancelled ? nil : PreparedPatchSummary(sections: sections)
    }
}

/// Readable summaries alongside text patches, shared by working and committed changes.
struct PatchSummaryView: View {
    let text: String
    @State private var prepared: PreparedPatchSummary?
    @State private var preparedText: String?

    var body: some View {
        Group {
        if preparedText == text, let prepared {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(prepared.sections.enumerated()), id: \.offset) { _, section in
                    switch section {
                    case .text(let text): HighlightedPatchText(text: text)
                    case .summary(let item): summary(item)
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            Text(AppLocalization.text("正在加载…")).appFont(size: 12).foregroundStyle(.secondary)
        }
        }
        .task(id: text) {
            guard preparedText != text else { return }
            let worker = Task.detached(priority: .userInitiated) { PreparedPatchSummary.prepare(text) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let result else { return }
            prepared = result
            preparedText = text
        }
    }

    private func summary(_ file: PreparedPatchSummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(AppLocalization.text(file.title), systemImage: file.isPureRename ? "arrow.right.doc.on.clipboard" : "doc")
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
            ForEach(Array(file.versions.enumerated()), id: \.offset) { _, version in
                path(version.1, title: version.0)
            }
            if let mode = file.mode {
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
