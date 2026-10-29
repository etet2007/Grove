import SwiftUI

/// Mount on first use, then retain the native view and its scroll/focus state.
/// Opacity-only hiding still proposes new sizes to every offscreen SwiftUI tree.
/// Inactive hosts are detached from the layout tree and keep their last viewport
/// until selected again; retaining the host preserves its SwiftUI state.
struct RetainedPane<Content: View>: NSViewRepresentable {
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> RetainedPaneContainer<Content> {
        RetainedPaneContainer()
    }

    func updateNSView(_ view: RetainedPaneContainer<Content>, context: Context) {
        view.update(isActive: isActive, content: content)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RetainedPaneContainer<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

final class RetainedPaneContainer<Content: View>: NSView {
    private var host: NSHostingView<Content>?
    private var isActive = false

    func update(isActive: Bool, content: () -> Content) {
        self.isActive = isActive
        setAccessibilityHidden(!isActive)
        guard isActive else {
            host?.removeFromSuperview()
            return
        }
        if let host {
            if host.superview == nil { addSubview(host) }
            host.rootView = content()
        } else {
            let host = NSHostingView(rootView: content())
            host.sizingOptions = []
            addSubview(host)
            self.host = host
        }
        needsLayout = true
    }

    // Empty inactive containers still overlap the selected pane in the ZStack.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }

    override func layout() {
        super.layout()
        guard isActive else { return }
        host?.frame = bounds
    }
}
