import AppKit
import QuartzCore
import SwiftUI

/// Read the selected row's current position only when presenting or dismissing.
/// Weak anchors avoid publishing geometry on every scroll/layout pass.
@MainActor final class DiffPreviewOrigin {
    private struct Anchor { weak var view: NSView? }
    private var anchors: [AnyHashable: Anchor] = [:]

    func register(_ view: NSView, for id: AnyHashable) { anchors[id] = Anchor(view: view) }
    func remove(_ view: NSView, for id: AnyHashable) {
        if anchors[id]?.view === view { anchors.removeValue(forKey: id) }
    }
    func screenRect(for id: AnyHashable?) -> NSRect? {
        guard let id, let view = anchors[id]?.view, let window = view.window else { return nil }
        let rect = view.visibleRect.intersection(view.bounds)
        guard rect.width > 1, rect.height > 1 else { return nil }
        return window.convertToScreen(view.convert(rect, to: nil))
    }
}

struct DiffPreviewAnchor: NSViewRepresentable {
    let origin: DiffPreviewOrigin
    let id: AnyHashable
    func makeCoordinator() -> Coordinator { Coordinator(origin: origin, id: id) }
    final class Coordinator {
        let origin: DiffPreviewOrigin
        let id: AnyHashable
        init(origin: DiffPreviewOrigin, id: AnyHashable) { self.origin = origin; self.id = id }
    }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        origin.register(view, for: id)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { origin.register(view, for: id) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.origin.remove(view, for: coordinator.id)
    }
}

private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A window-scoped presenter keeps each Grove window's preview and keyboard events independent.
struct DiffPreviewWindow<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var moveFile: (Int) -> Void
    var onClose: () -> Void = {}
    var origin: DiffPreviewOrigin? = nil
    var selectionID: AnyHashable? = nil
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.sourceRect = origin?.screenRect(for: selectionID)
        coordinator.moveFile = moveFile
        coordinator.dismiss = { isPresented = false; onClose() }
        guard isPresented else { coordinator.close(); return }
        let root = AnyView(content().preferredColorScheme(.dark))
        if let host = coordinator.host {
            host.rootView = root
        } else if let parent = view.window {
            coordinator.show(root, parent: parent)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close(animated: false) }

    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        private(set) var window: NSWindow?
        private(set) var host: NSHostingView<AnyView>?
        var moveFile: (Int) -> Void = { _ in }
        var dismiss: () -> Void = {}
        private var keyMonitor: Any?
        private var parentCloseObserver: NSObjectProtocol?
        private weak var parent: NSWindow?
        var sourceRect: NSRect?
        private var snapshotLayer: CALayer?
        private var isClosing = false
        private var isOpening = false
        private var animationGeneration = 0

        func show(_ root: AnyView, parent: NSWindow, animated: Bool = true) {
            guard window == nil else { return }
            self.parent = parent
            let frame = parent.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let window = PreviewWindow(contentRect: frame, styleMask: [.borderless, .resizable],
                                  backing: .buffered, defer: false)
            window.title = AppLocalization.text("Diff 预览")
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenAuxiliary]
            window.animationBehavior = .none
            window.hasShadow = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.minSize = NSSize(width: 700, height: 450)
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: root)
            let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
            container.wantsLayer = true
            host.frame = container.bounds
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            window.contentView = container
            window.setFrame(frame, display: false)
            window.delegate = self
            self.window = window
            self.host = host
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                // Let search fields and expanded controls keep their editing/navigation keys.
                guard !(self.window?.firstResponder is NSTextView),
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                switch event.keyCode {
                case 53: self.close(); return nil
                case 49:
                    if !event.isARepeat { self.close() }
                    return nil
                case 126: self.moveFile(-1); return nil
                case 125: self.moveFile(1); return nil
                default: return event
                }
            }
            parentCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                          object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.parent = nil
                    self?.close(animated: false)
                }
            }
            host.layoutSubtreeIfNeeded()
            if animated { prepareSnapshot() }
            if animated { animate(opening: true) }
            window.makeKeyAndOrderFront(nil)
        }

        /// Animate a cached surface at a fixed window size. The diff never relayouts per frame.
        private func prepareSnapshot() {
            guard snapshotLayer == nil, let window, let host, let container = window.contentView,
                  let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { return }
            let layer = CALayer()
            layer.contents = image
            layer.contentsScale = window.backingScaleFactor
            layer.frame = container.bounds
            layer.masksToBounds = true
            container.layer?.addSublayer(layer)
            snapshotLayer = layer
            host.isHidden = true
        }

        private func animate(opening: Bool) {
            guard let window else { return }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            guard let layer = snapshotLayer, let container = window.contentView else {
                if !opening { window.close() }
                return
            }
            animationGeneration += 1
            let generation = animationGeneration
            let full = container.bounds
            let origin = sourceRect.map {
                NSRect(x: $0.minX - window.frame.minX, y: $0.minY - window.frame.minY,
                       width: $0.width, height: $0.height)
            } ?? full.insetBy(dx: full.width * 0.04, dy: full.height * 0.04)
            let current = layer.presentation()
            let start = opening ? (reduceMotion ? full : origin) : (current?.frame ?? (isOpening ? origin : full))
            let end = opening || reduceMotion ? full : origin
            let startOpacity: Float = opening ? 0 : (current?.opacity ?? (isOpening ? 0 : 1))
            isOpening = opening
            layer.removeAllAnimations()
            let duration = reduceMotion ? 0.12 : (opening ? 0.3 : 0.22)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = end
            layer.opacity = opening ? 1 : 0
            layer.cornerRadius = opening ? 0 : WorkbenchStyle.controlRadius
            CATransaction.setCompletionBlock { [weak self, weak window] in
                DispatchQueue.main.async {
                    guard let self, self.animationGeneration == generation, self.window === window else { return }
                    if opening {
                        self.isOpening = false
                        self.host?.isHidden = false
                        self.snapshotLayer?.removeFromSuperlayer()
                        self.snapshotLayer = nil
                    } else {
                        window?.close()
                    }
                }
            }
            let bounds = CABasicAnimation(keyPath: "bounds")
            bounds.fromValue = NSValue(rect: NSRect(origin: .zero, size: start.size))
            bounds.toValue = NSValue(rect: NSRect(origin: .zero, size: end.size))
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: NSPoint(x: start.midX, y: start.midY))
            position.toValue = NSValue(point: NSPoint(x: end.midX, y: end.midY))
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = startOpacity
            opacity.toValue = opening ? 1 : 0
            let corner = CABasicAnimation(keyPath: "cornerRadius")
            corner.fromValue = opening ? WorkbenchStyle.controlRadius : 0
            corner.toValue = opening ? 0 : WorkbenchStyle.controlRadius
            let group = CAAnimationGroup()
            group.animations = [bounds, position, opacity, corner]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            layer.add(group, forKey: "previewTransition")
            CATransaction.commit()
        }

        func close(animated: Bool = true) {
            guard let window else { return }
            if !animated {
                animationGeneration += 1
                window.close()
                return
            }
            guard !isClosing else { return }
            isClosing = true
            prepareSnapshot()
            animate(opening: false)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            close()
            return false
        }

        func windowWillClose(_ notification: Notification) {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            if let parentCloseObserver { NotificationCenter.default.removeObserver(parentCloseObserver) }
            keyMonitor = nil
            parentCloseObserver = nil
            animationGeneration += 1
            snapshotLayer?.removeFromSuperlayer()
            snapshotLayer = nil
            isClosing = false
            isOpening = false
            window = nil
            host = nil
            parent?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [dismiss] in dismiss() }
        }
    }
}

struct DiffPreviewToolbar: View {
    let position: Int
    let count: Int
    let moveFile: (Int) -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(AppLocalization.text("Diff 预览")).appFont(size: 13, weight: .semibold)
            Text(AppLocalization.text("↑ / ↓ 切换文件 · Esc 关闭")).appFont(size: 11).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(position + 1) / \(count)").appFont(size: 11, design: .monospaced)
            Button { moveFile(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(position <= 0).help(AppLocalization.text("上一个文件"))
                .accessibilityLabel(AppLocalization.text("上一个文件"))
            Button { moveFile(1) } label: { Image(systemName: "chevron.down") }
                .disabled(position < 0 || position >= count - 1).help(AppLocalization.text("下一个文件"))
                .accessibilityLabel(AppLocalization.text("下一个文件"))
            Button(action: close) { Image(systemName: "xmark") }
                .help(AppLocalization.text("关闭预览"))
                .accessibilityLabel(AppLocalization.text("关闭预览"))
        }
        .buttonStyle(WorkbenchButtonStyle())
        .padding(12)
        .background(WorkbenchStyle.sidebar)
    }
}
