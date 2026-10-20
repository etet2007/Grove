import SwiftUI
import WebKit

private struct MarkdownReviewActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var markdownReviewIsActive: Bool {
        get { self[MarkdownReviewActiveKey.self] }
        set { self[MarkdownReviewActiveKey.self] = newValue }
    }
}

struct MarkdownVersion {
    var body: String?
    var message: String?
}

struct MarkdownVersions {
    let old: MarkdownVersion
    let new: MarkdownVersion
}

extension GitClient {
    /// Read complete versions rather than attempting to reconstruct a document from diff hunks.
    static func markdownVersions(path: String, oldPath: String? = nil, in checkout: String,
                                 mode: DiffMode = .unstaged, untracked: Bool = false,
                                 commit: String? = nil) -> MarkdownVersions {
        let limit = 2_000_000
        func version(_ data: Data) -> MarkdownVersion {
            guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                return MarkdownVersion(message: "此文件不是 UTF-8 文本")
            }
            return MarkdownVersion(body: MarkdownPreview.body(text))
        }
        func blob(_ revision: String) -> MarkdownVersion {
            guard let rawSize = try? text(["cat-file", "-s", revision], in: checkout),
                  let size = Int(rawSize.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return MarkdownVersion(message: "此版本无文件")
            }
            guard size <= limit else { return MarkdownVersion(message: "Markdown 超过 2 MB，请查看源码 diff") }
            guard let data = try? run(["cat-file", "blob", revision], in: checkout), data.count <= limit else {
                return MarkdownVersion(message: "无法读取 Markdown")
            }
            return version(data)
        }
        func working() -> MarkdownVersion {
            let url = URL(fileURLWithPath: checkout).appendingPathComponent(path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else {
                return MarkdownVersion(message: "此版本无普通文件")
            }
            guard (values.fileSize ?? 0) <= limit else { return MarkdownVersion(message: "Markdown 超过 2 MB，请查看源码 diff") }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return MarkdownVersion(message: "无法读取 Markdown") }
            defer { try? handle.close() }
            do {
                let data = try handle.read(upToCount: limit + 1) ?? Data()
                guard data.count <= limit else { return MarkdownVersion(message: "Markdown 超过 2 MB，请查看源码 diff") }
                return version(data)
            } catch {
                return MarkdownVersion(message: "无法读取 Markdown")
            }
        }
        if let commit {
            return MarkdownVersions(old: blob(commit + "^1:" + (oldPath ?? path)), new: blob(commit + ":" + path))
        }
        if untracked {
            return MarkdownVersions(old: MarkdownVersion(message: "此版本无文件"),
                                    new: mode == .staged ? MarkdownVersion(message: "未跟踪文件没有已暂存修改。") : working())
        }
        switch mode {
        case .unstaged: return MarkdownVersions(old: blob(":" + path), new: working())
        case .staged: return MarkdownVersions(old: blob("HEAD:" + (oldPath ?? path)), new: blob(":" + path))
        case .all: return MarkdownVersions(old: blob("HEAD:" + (oldPath ?? path)), new: working())
        }
    }
}

struct MarkdownReviewView: View {
    let path: String
    var oldPath: String? = nil
    let checkout: String
    var mode: DiffMode = .unstaged
    var untracked = false
    var commit: String? = nil
    var revision = ""
    var preferOld = false
    let oldTitle: String
    let newTitle: String
    @State private var versions: MarkdownVersions?
    @State private var showingOld = false
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @AppStorage("markdownPreviewZoom") private var storedZoom = 1.0
    @Environment(\.markdownReviewIsActive) private var isActive

    private var zoom: Double { storedZoom.isFinite ? min(2, max(0.7, storedZoom)) : 1 }

    private var requestID: [String] { [checkout, path, oldPath ?? "", mode.rawValue, String(untracked), commit ?? "", revision] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                WorkbenchSegments(title: "阅读版本", values: [false, true], selection: $showingOld) {
                    AppLocalization.text($0 ? oldTitle : newTitle)
                }
                Spacer()
                zoomControls
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let versions {
                let version = showingOld ? versions.old : versions.new
                if let body = version.body {
                    MarkdownWebView(html: MarkdownPreview.document(body: body, fontSize: fontSize), zoom: zoom,
                                    shortcutsEnabled: isActive) { action in
                        switch action {
                        case .smaller: changeZoom(-0.1)
                        case .larger: changeZoom(0.1)
                        case .reset: storedZoom = 1
                        }
                    }
                } else {
                    ContentUnavailableView(AppLocalization.text(version.message ?? "无法读取 Markdown"), systemImage: "doc.text")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { showingOld = preferOld }
        .task(id: requestID) {
            let session = GitReadSession()
            await withTaskCancellationHandler {
                let result = await Task.detached(priority: .utility) {
                    GitClient.$readSession.withValue(session) {
                        GitClient.markdownVersions(path: path, oldPath: oldPath, in: checkout, mode: mode,
                                                   untracked: untracked, commit: commit)
                    }
                }.value
                guard !Task.isCancelled else { return }
                versions = result
            } onCancel: { session.cancel() }
        }
    }

    private func changeZoom(_ delta: Double) {
        storedZoom = min(2, max(0.7, ((zoom + delta) * 10).rounded() / 10))
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { changeZoom(-0.1) } label: { Text(verbatim: "A−") }
                .keyboardShortcut(isActive ? KeyboardShortcut("-", modifiers: .command) : nil)
                .help(AppLocalization.text("缩小 Markdown 字体（⌘−）"))
                .accessibilityLabel(AppLocalization.text("缩小 Markdown 字体"))
                .disabled(zoom <= 0.7)
            Button { storedZoom = 1 } label: {
                Text(verbatim: "\(Int((zoom * 100).rounded()))%")
                    .monospacedDigit().frame(minWidth: 38)
            }
            .keyboardShortcut(isActive ? KeyboardShortcut("0", modifiers: .command) : nil)
            .help(AppLocalization.text("恢复 Markdown 默认字号（⌘0）"))
            .accessibilityLabel(AppLocalization.text("恢复 Markdown 默认字号"))
            .accessibilityValue(Text(verbatim: "\(Int((zoom * 100).rounded()))%"))
            Button { changeZoom(0.1) } label: { Text(verbatim: "A+") }
                .keyboardShortcut(isActive ? KeyboardShortcut("=", modifiers: .command) : nil)
                .help(AppLocalization.text("放大 Markdown 字体（⌘+）"))
                .accessibilityLabel(AppLocalization.text("放大 Markdown 字体"))
                .disabled(zoom >= 2)
        }
        .appFont(size: 12, weight: .medium)
        .buttonStyle(WorkbenchButtonStyle())
        .background {
            // Accept both Command-= and Command-Shift-= on standard keyboards.
            Button("") { changeZoom(0.1) }
                .keyboardShortcut(isActive ? KeyboardShortcut("+", modifiers: .command) : nil)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                .disabled(zoom >= 2)
        }
        .disabled(!isActive)
    }
}

enum MarkdownZoomAction { case smaller, larger, reset }

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    var zoom = 1.0
    var shortcutsEnabled = true
    var onZoom: ((MarkdownZoomAction) -> Void)? = nil

    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        var shortcutsEnabled = false
        var onZoom: ((MarkdownZoomAction) -> Void)?
        var keyMonitor: Any?

        func installKeyMonitor(for view: WKWebView) {
            // WKContentView can consume zoom keys before SwiftUI's buttons see them.
            // Intercept only the visible preview's key window, including text selection.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, self.shortcutsEnabled, let onZoom = self.onZoom,
                      let window = view?.window, window === NSApp.keyWindow else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard modifiers == .command || modifiers == [.command, .shift] else { return event }
                let action: MarkdownZoomAction
                switch event.charactersIgnoringModifiers {
                case "-", "_": action = .smaller
                case "=", "+": action = .larger
                case "0" where modifiers == .command: action = .reset
                default: return event
                }
                onZoom(action)
                return nil
            }
        }

        func removeKeyMonitor() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        deinit { removeKeyMonitor() }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(url.scheme == "about" ? .allow : .cancel)
                }
            } else {
                decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.installKeyMonitor(for: view)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.shortcutsEnabled = shortcutsEnabled
        context.coordinator.onZoom = onZoom
        if view.pageZoom != zoom { view.pageZoom = zoom }
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
    }
}
