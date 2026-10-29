import SwiftUI

private enum DiffSearchSource {
    enum ID: Equatable {
        case split(UUID), plain(String), patch(String)
    }
    case split(SplitDiff), plain(String), patch(String)
    var id: ID {
        switch self {
        case .split(let diff): return .split(diff.contentID)
        case .plain(let text): return .plain(text)
        case .patch(let text): return .patch(text)
        }
    }
}

struct DiffSearchLine: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
}

private struct DiffSearchResult {
    let matches: [Int]
    let matchingRows: Set<Int>
}

private struct DiffSearchIndex {
    let lines: [DiffSearchLine]
    let hunks: [Int]
    let displayLines: [DiffSearchLine]

    static func prepare(_ source: DiffSearchSource) -> DiffSearchIndex? {
        var lines: [DiffSearchLine] = []
        var hunks: [Int] = []
        var displayLines: [DiffSearchLine] = []
        switch source {
        case .split(let diff):
            lines.reserveCapacity(diff.rows.count)
            for (offset, row) in diff.rows.enumerated() {
                if offset.isMultiple(of: 512), Task.isCancelled { return nil }
                lines.append(DiffSearchLine(id: row.id, text: [row.old?.text, row.new?.text].compactMap { $0 }.joined(separator: "\n")))
                if row.old?.kind == .hunk || row.new?.kind == .hunk { hunks.append(row.id) }
            }
        case .plain(let text), .patch(let text):
            let readable: String
            if case .patch = source { readable = PatchPresentation.readableText(text) }
            else { readable = text }
            let rawLines = readable.components(separatedBy: "\n")
            lines.reserveCapacity(rawLines.count)
            for (offset, line) in rawLines.enumerated() {
                if offset.isMultiple(of: 512), Task.isCancelled { return nil }
                lines.append(DiffSearchLine(id: offset, text: line))
                if line.hasPrefix("@@ ") { hunks.append(offset) }
            }
            displayLines = lines
        }
        return Task.isCancelled ? nil : DiffSearchIndex(lines: lines, hunks: hunks, displayLines: displayLines)
    }

    func find(_ query: String) -> DiffSearchResult? {
        var matches: [Int] = []
        for (offset, line) in lines.enumerated() {
            if offset.isMultiple(of: 512), Task.isCancelled { return nil }
            if line.text.localizedCaseInsensitiveContains(query) { matches.append(line.id) }
        }
        guard !Task.isCancelled else { return nil }
        return DiffSearchResult(matches: matches, matchingRows: Set(matches))
    }
}

@MainActor final class DiffSearch: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published private(set) var isSearching = false
    @Published private(set) var matches: [Int] = []
    @Published private(set) var matchingRows: Set<Int> = []
    @Published private(set) var displayLines: [DiffSearchLine] = []
    @Published private(set) var selected = 0
    @Published private(set) var targetRow: Int?
    @Published private(set) var navigationID = UUID()
    private var index: DiffSearchIndex?
    private var sourceID: DiffSearchSource.ID?
    private var contentGeneration = 0
    private var searchGeneration = 0
    private var indexTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    deinit { indexTask?.cancel(); searchTask?.cancel() }

    func prepare(_ diff: SplitDiff) { prepare(.split(diff)) }
    func prepare(text: String) { prepare(.plain(text)) }
    func prepare(patch: String) { prepare(.patch(patch)) }

    private func prepare(_ source: DiffSearchSource) {
        guard sourceID != source.id else { return }
        sourceID = source.id
        contentGeneration += 1
        let generation = contentGeneration
        indexTask?.cancel()
        searchTask?.cancel()
        index = nil
        displayLines = []
        clearResults()
        isSearching = !query.isEmpty
        indexTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { DiffSearchIndex.prepare(source) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.contentGeneration == generation, let result else { return }
            self.index = result
            self.displayLines = result.displayLines
            self.scheduleSearch()
        }
    }

    private func clearResults() {
        matches = []; matchingRows = []; selected = 0; targetRow = nil
        navigationID = UUID()
    }

    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        clearResults()
        guard !query.isEmpty else { isSearching = false; return }
        isSearching = true
        guard let index else { return } // The latest query will run when preparation completes.
        let query = query
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            let worker = Task.detached(priority: .userInitiated) { index.find(query) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.searchGeneration == generation, let result else { return }
            self.matches = result.matches
            self.matchingRows = result.matchingRows
            self.selected = 0
            self.targetRow = result.matches.first
            self.isSearching = false
            self.navigationID = UUID()
        }
    }

    func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        selected = (selected + delta + matches.count) % matches.count
        targetRow = matches[selected]
        navigationID = UUID()
    }
    func moveHunk(_ delta: Int) {
        guard let hunks = index?.hunks, !hunks.isEmpty else { return }
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
            Text(search.isSearching ? "…" : search.matches.isEmpty ? "0" : "\(search.selected + 1)/\(search.matches.count)")
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
                        ForEach(search.displayLines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .appFont(size: 12, design: .monospaced)
                                .foregroundStyle(line.text.hasPrefix("+") ? .green : line.text.hasPrefix("-") ? .red : .primary)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                                .background(search.matchingRows.contains(line.id) ? Color.yellow.opacity(search.targetRow == line.id ? 0.35 : 0.14) : .clear)
                                .id(line.id)
                        }
                    }.padding(16)
                } else {
                    PatchSummaryView(text: text).frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
                }
            }
            .onChange(of: search.navigationID) { _, _ in
                if let row = search.targetRow { proxy.scrollTo(row, anchor: .center) }
            }
            .task(id: text) {
                guard !Task.isCancelled else { return }
                search.prepare(patch: text)
            }
        }
    }
}
