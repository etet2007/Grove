import SwiftUI

struct SidebarSplitView<Sidebar: View, Content: View>: NSViewRepresentable {
    let initialWidth: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NavigationSplitView {
        let split = NavigationSplitView()
        split.preferredSidebarWidth = initialWidth
        for pane in [NSHostingView(rootView: AnyView(sidebar())), NSHostingView(rootView: AnyView(content()))] {
            pane.sizingOptions = []
            split.addArrangedSubview(pane)
        }
        return split
    }

    // This split fills its parent; it has no intrinsic content size. The default
    // AppKit fitting pass walks every nested hosting view and its constraints on
    // each window resize, even though the parent has already supplied the size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NavigationSplitView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ split: NavigationSplitView, context: Context) {
        (split.arrangedSubviews[0] as? NSHostingView<AnyView>)?.rootView = AnyView(sidebar())
        (split.arrangedSubviews[1] as? NSHostingView<AnyView>)?.rootView = AnyView(content())
    }
}

/// Window resizing allocates extra space to content; divider dragging chooses a new width.
final class NavigationSplitView: NSSplitView, NSSplitViewDelegate {
    var preferredSidebarWidth: CGFloat = 280
    private var applyingLayout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true
        dividerStyle = .thin
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var maximumSidebarWidth: CGFloat { max(0, bounds.width - dividerThickness - 710) }

    override func adjustSubviews() {
        guard arrangedSubviews.count == 2 else { return }
        applyingLayout = true
        defer { applyingLayout = false }
        let available = max(0, bounds.width - dividerThickness)
        let width = min(maximumSidebarWidth, max(220, preferredSidebarWidth))
        arrangedSubviews[0].frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        arrangedSubviews[1].frame = NSRect(x: width + dividerThickness, y: 0,
                                          width: max(0, available - width), height: bounds.height)
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        adjustSubviews()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applyingLayout, let first = arrangedSubviews.first, first.frame.width > 0 else { return }
        preferredSidebarWidth = first.frame.width
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat { min(220, maximumSidebarWidth) }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat { maximumSidebarWidth }

    private var dragRect: NSRect {
        NSRect(x: (arrangedSubviews.first?.frame.maxX ?? 0) - 3, y: 0,
               width: dividerThickness + 6, height: bounds.height)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(dragRect, cursor: .resizeLeftRight)
    }

    func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect { dragRect }
}
