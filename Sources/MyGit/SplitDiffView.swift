import SwiftUI

struct SplitDiffView: View {
    let diff: SplitDiff
    let oldTitle: String
    let newTitle: String
    let resetID: String
    var singleSide: DiffSide? = nil
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @State private var horizontalSync = HorizontalScrollSync()

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = singleSide == nil ? max(200, (geometry.size.width - 1) / 2) : geometry.size.width
            let contentWidth = max(paneWidth, min(16_000, CGFloat(diff.rows.flatMap { [$0.old, $0.new] }.compactMap { $0?.text }.map { text in
                text.unicodeScalars.reduce(0) { $0 + ($1.value > 127 ? 2 : 1) }
            }.max() ?? 0) * 7.25 * AppTypography.scale(for: fontSize) + 72 * AppTypography.scale(for: fontSize)))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if singleSide != .new { title(oldTitle).frame(width: paneWidth) }
                    if singleSide == nil { Divider() }
                    if singleSide != .old { title(newTitle).frame(width: paneWidth) }
                }
                .frame(height: 34)
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    if singleSide != .new { pane(\.old, side: .old, width: paneWidth, contentWidth: contentWidth) }
                    if singleSide == nil { Rectangle().fill(.separator).frame(width: 1) }
                    if singleSide != .old { pane(\.new, side: .new, width: paneWidth, contentWidth: contentWidth) }
                }
            }
        }
    }

    private func title(_ value: String) -> some View {
        Text(value)
            .appFont(size: 12, weight: .semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }

    private func pane(_ lines: KeyPath<DiffRow, DiffLine?>, side: DiffSide,
                      width: CGFloat, contentWidth: CGFloat) -> some View {
        SynchronizedHorizontalScrollView(
            rows: diff.rows,
            lines: lines,
            contentWidth: contentWidth,
            fontScale: AppTypography.scale(for: fontSize),
            side: side,
            sync: horizontalSync
        )
        .frame(width: width)
    }
}

private struct DiffRowsColumn: View {
    let rows: ArraySlice<DiffRow>
    let lines: KeyPath<DiffRow, DiffLine?>
    let width: CGFloat
    var fontScale: CGFloat = 1
    private var rowHeight: CGFloat { 21 * fontScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in line(row[keyPath: lines], width: width) }
        }
        .frame(width: width, height: CGFloat(rows.count) * rowHeight, alignment: .topLeading)
    }

    private func line(_ value: DiffLine?, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(value?.number.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 48 * fontScale, alignment: .trailing)
                .padding(.trailing, 12 * fontScale)
            Text(value?.text ?? "")
                .foregroundStyle(value?.kind == .heading || value?.kind == .hunk ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12 * fontScale, design: .monospaced))
        .frame(width: width, height: rowHeight, alignment: .leading)
        .background(background(for: value?.kind))
    }

    private func background(for kind: DiffLineKind?) -> Color {
        switch kind {
        case .removed: Color.red.opacity(0.17)
        case .added: Color.green.opacity(0.17)
        case .heading: Color.secondary.opacity(0.10)
        case .hunk: Color.accentColor.opacity(0.12)
        case .context, nil: .clear
        }
    }
}

enum DiffSide: Hashable {
    case old, new
}

final class HorizontalScrollSync {
    private final class WeakScrollView {
        weak var value: NSScrollView?
        init(_ value: NSScrollView) { self.value = value }
    }

    private var scrollViews: [DiffSide: WeakScrollView] = [:]
    private var isSynchronizing = false

    func register(_ scrollView: NSScrollView, for side: DiffSide) {
        scrollViews[side] = WeakScrollView(scrollView)
    }

    func didScroll(_ source: NSScrollView, side: DiffSide) {
        guard !isSynchronizing else { return }
        let otherSide: DiffSide = side == .old ? .new : .old
        guard let target = scrollViews[otherSide]?.value else { return }
        let maximum = max(0, (target.documentView?.frame.width ?? 0) - target.contentView.bounds.width)
        let x = min(max(0, source.contentView.bounds.origin.x), maximum)
        let maximumY = max(0, (target.documentView?.frame.height ?? 0) - target.contentView.bounds.height)
        let y = min(max(0, source.contentView.bounds.origin.y), maximumY)
        guard abs(target.contentView.bounds.origin.x - x) > 0.5 ||
              abs(target.contentView.bounds.origin.y - y) > 0.5 else { return }
        isSynchronizing = true
        target.contentView.scroll(to: NSPoint(x: x, y: y))
        target.reflectScrolledClipView(target.contentView)
        isSynchronizing = false
    }
}

// The document retains the full scroll extent, but hosts only the visible rows
// and a small buffer. A LazyVStack inside a full-height NSHostingView would still
// see the entire document as its viewport.
final class VirtualizedDiffDocumentView: NSView {
    private var fontScale: CGFloat = 1
    private var rowHeight: CGFloat { 21 * fontScale }
    private let lines: KeyPath<DiffRow, DiffLine?>
    private var rows: [DiffRow] = []
    private var columnWidth: CGFloat = 0
    private let host: NSHostingView<DiffRowsColumn>
    private(set) var renderedRowRange = 0..<0

    override var isFlipped: Bool { true }

    init(lines: KeyPath<DiffRow, DiffLine?>) {
        self.lines = lines
        host = NSHostingView(rootView: DiffRowsColumn(rows: [], lines: lines, width: 0))
        super.init(frame: .zero)
        host.sizingOptions = []
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(rows: [DiffRow], width: CGFloat, fontScale: CGFloat = 1) {
        let changed = self.rows != rows || columnWidth != width || self.fontScale != fontScale
        guard changed else { return }
        self.rows = rows
        columnWidth = width
        self.fontScale = fontScale
        frame.size = NSSize(width: width, height: CGFloat(rows.count) * rowHeight)
        updateVisibleRows(force: true)
    }

    override func layout() {
        super.layout()
        updateVisibleRows()
    }

    func updateVisibleRows(force: Bool = false) {
        guard let scrollView = enclosingScrollView else { return }
        let viewport = scrollView.documentVisibleRect
        let first = min(rows.count, max(0, Int(floor(viewport.minY / rowHeight)) - 8))
        let last = min(rows.count, max(first, Int(ceil(viewport.maxY / rowHeight)) + 8))
        let range = first..<last
        guard force || range != renderedRowRange else { return }
        renderedRowRange = range
        host.rootView = DiffRowsColumn(rows: rows[range], lines: lines, width: columnWidth, fontScale: fontScale)
        host.frame = NSRect(x: 0, y: CGFloat(first) * rowHeight,
                            width: columnWidth, height: CGFloat(range.count) * rowHeight)
    }
}

private struct SynchronizedHorizontalScrollView: NSViewRepresentable {
    let rows: [DiffRow]
    let lines: KeyPath<DiffRow, DiffLine?>
    let contentWidth: CGFloat
    let fontScale: CGFloat
    let side: DiffSide
    let sync: HorizontalScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(side: side, sync: sync) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = VirtualizedDiffDocumentView(lines: lines)
        sync.register(scrollView, for: side)
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let document = scrollView.documentView as? VirtualizedDiffDocumentView else { return }
        document.setContent(rows: rows, width: contentWidth, fontScale: fontScale)
        document.updateVisibleRows()
    }

    final class Coordinator {
        let side: DiffSide
        let sync: HorizontalScrollSync
        private var observer: NSObjectProtocol?

        init(side: DiffSide, sync: HorizontalScrollSync) {
            self.side = side
            self.sync = sync
        }

        func observe(_ scrollView: NSScrollView) {
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: nil
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                (scrollView.documentView as? VirtualizedDiffDocumentView)?.updateVisibleRows()
                self.sync.didScroll(scrollView, side: self.side)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
