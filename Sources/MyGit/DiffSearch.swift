import SwiftUI

@MainActor final class DiffSearch: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" { didSet { rebuild() } }
    @Published private(set) var matches: [Int] = []
    @Published private(set) var selected = 0
    @Published private(set) var targetRow: Int?
    @Published private(set) var navigationID = UUID()
    private var lines: [(Int, String)] = []
    private var hunks: [Int] = []
    private var contentID: String = ""

    func prepare(_ diff: SplitDiff) {
        guard contentID != diff.contentID.uuidString else { return }
        contentID = diff.contentID.uuidString
        lines = diff.rows.map { ($0.id, [$0.old?.text, $0.new?.text].compactMap { $0 }.joined(separator: "\n")) }
        hunks = diff.rows.filter { $0.old?.kind == .hunk || $0.new?.kind == .hunk }.map(\.id)
        rebuild()
    }
    func prepare(text: String) {
        guard contentID != text else { return }
        contentID = text
        lines = text.components(separatedBy: "\n").enumerated().map { ($0.offset, $0.element) }
        hunks = lines.filter { $0.1.hasPrefix("@@ ") }.map { $0.0 }
        rebuild()
    }
    private func rebuild() {
        matches = query.isEmpty ? [] : lines.filter { $0.1.localizedCaseInsensitiveContains(query) }.map { $0.0 }
        selected = 0
        targetRow = matches.first
        navigationID = UUID()
    }
    func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        selected = (selected + delta + matches.count) % matches.count
        targetRow = matches[selected]
        navigationID = UUID()
    }
    func moveHunk(_ delta: Int) {
        guard !hunks.isEmpty else { return }
        let current = targetRow ?? (delta > 0 ? -1 : Int.max)
        targetRow = delta > 0 ? (hunks.first { $0 > current } ?? hunks[0]) : (hunks.last { $0 < current } ?? hunks.last)
        navigationID = UUID()
    }
}

struct DiffSearchBar: View {
    @ObservedObject var search: DiffSearch
    var body: some View {
        HStack(spacing: 8) {
            WorkbenchSearchField(title: "搜索 diff（按匹配行）", text: $search.query, autofocus: true)
                .onSubmit { search.move(1) }
            Text(search.matches.isEmpty ? "0" : "\(search.selected + 1)/\(search.matches.count)")
                .monospacedDigit().foregroundStyle(.secondary)
            Button { search.move(-1) } label: { Image(systemName: "chevron.up") }.help(AppLocalization.text("上一个匹配"))
                .disabled(search.matches.isEmpty)
            Button { search.move(1) } label: { Image(systemName: "chevron.down") }.help(AppLocalization.text("下一个匹配"))
                .disabled(search.matches.isEmpty)
            Button { search.moveHunk(-1) } label: { Image(systemName: "arrow.up.to.line") }.help(AppLocalization.text("上一个修改块"))
            Button { search.moveHunk(1) } label: { Image(systemName: "arrow.down.to.line") }.help(AppLocalization.text("下一个修改块"))
            Button { search.isPresented = false; search.query = "" } label: { Image(systemName: "xmark") }
                .help(AppLocalization.text("关闭搜索"))
        }
        .appFont(size: 11).buttonStyle(WorkbenchButtonStyle(size: .compact)).padding(8)
        .onExitCommand { search.isPresented = false; search.query = "" }
    }
}

struct SearchablePatchView: View {
    let text: String
    @ObservedObject var search: DiffSearch
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                if search.isPresented {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(PatchPresentation.readableText(text).components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .appFont(size: 12, design: .monospaced)
                                .foregroundStyle(line.hasPrefix("+") ? .green : line.hasPrefix("-") ? .red : .primary)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                                .background(search.matches.contains(index) ? Color.yellow.opacity(search.targetRow == index ? 0.35 : 0.14) : .clear)
                                .id(index)
                        }
                    }.padding(16)
                } else {
                    PatchSummaryView(text: text).frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                }
            }
            .onChange(of: search.navigationID) { _, _ in
                if let row = search.targetRow { proxy.scrollTo(row, anchor: .center) }
            }
            .task(id: text) { search.prepare(text: PatchPresentation.readableText(text)) }
        }
    }
}
