import SwiftUI

struct SplitDiffView: View {
    let diff: SplitDiff
    let oldTitle: String
    let newTitle: String
    let resetID: String
    @State private var horizontalSync = HorizontalScrollSync()

    var body: some View {
        GeometryReader { geometry in
            let paneWidth = max(200, (geometry.size.width - 1) / 2)
            let contentWidth = max(paneWidth, min(16_000, CGFloat(diff.rows.flatMap { [$0.old, $0.new] }.compactMap { $0?.text }.map { text in
                text.unicodeScalars.reduce(0) { $0 + ($1.value > 127 ? 2 : 1) }
            }.max() ?? 0) * 7.25 + 72))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    title(oldTitle).frame(width: paneWidth)
                    Divider()
                    title(newTitle).frame(width: paneWidth)
                }
                .frame(height: 34)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            pane(\.old, side: .old, width: paneWidth, contentWidth: contentWidth)
                            Rectangle().fill(.separator).frame(width: 1)
                            pane(\.new, side: .new, width: paneWidth, contentWidth: contentWidth)
                        }
                        .id("split-top")
                    }
                    .onAppear { proxy.scrollTo("split-top", anchor: .top) }
                    .onChange(of: resetID) { _, _ in proxy.scrollTo("split-top", anchor: .top) }
                }
            }
        }
    }

    private func title(_ value: String) -> some View {
        Text(value)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }

    private func pane(_ lines: KeyPath<DiffRow, DiffLine?>, side: DiffSide,
                      width: CGFloat, contentWidth: CGFloat) -> some View {
        SynchronizedHorizontalScrollView(
            content: DiffRowsColumn(rows: diff.rows, lines: lines, width: contentWidth),
            contentWidth: contentWidth,
            contentHeight: CGFloat(diff.rows.count) * 21,
            side: side,
            sync: horizontalSync
        )
        .frame(width: width, height: CGFloat(diff.rows.count) * 21 + 14)
    }
}

private struct DiffRowsColumn: View {
    let rows: [DiffRow]
    let lines: KeyPath<DiffRow, DiffLine?>
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in line(row[keyPath: lines], width: width) }
        }
        .frame(width: width, height: CGFloat(rows.count) * 21, alignment: .topLeading)
    }

    private func line(_ value: DiffLine?, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(value?.number.map(String.init) ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 12)
            Text(value?.text ?? "")
                .foregroundStyle(value?.kind == .heading || value?.kind == .hunk ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(width: width, height: 21, alignment: .leading)
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
        guard abs(target.contentView.bounds.origin.x - x) > 0.5 else { return }
        isSynchronizing = true
        target.contentView.scroll(to: NSPoint(x: x, y: target.contentView.bounds.origin.y))
        target.reflectScrolledClipView(target.contentView)
        isSynchronizing = false
    }
}

private struct SynchronizedHorizontalScrollView: NSViewRepresentable {
    let content: DiffRowsColumn
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let side: DiffSide
    let sync: HorizontalScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(side: side, sync: sync) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        scrollView.documentView = host
        sync.register(scrollView, for: side)
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let host = scrollView.documentView as? NSHostingView<DiffRowsColumn> else { return }
        host.rootView = content
        host.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
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
                self.sync.didScroll(scrollView, side: self.side)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
