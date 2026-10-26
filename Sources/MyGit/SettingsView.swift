import SwiftUI

// App-wide preferences are separate from each window's engineering configuration.
enum AppTypography {
    static let fontSizeKey = "appFontSize"
    static let defaultFontSize = 12.0
    static let fontSizeRange = 10.0...18.0

    static func scale(for fontSize: Double) -> CGFloat {
        guard fontSize.isFinite else { return 1 }
        return CGFloat(min(fontSizeRange.upperBound, max(fontSizeRange.lowerBound, fontSize)) / defaultFontSize)
    }
}

private struct AppFontModifier: ViewModifier {
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * AppTypography.scale(for: fontSize), weight: weight, design: design))
    }
}

extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, commit, updates
    var id: String { rawValue }
    var title: String { switch self { case .general: "通用"; case .commit: "提交"; case .updates: "应用更新" } }
    var icon: String { switch self { case .general: "slider.horizontal.3"; case .commit: "checkmark.circle"; case .updates: "arrow.down.circle" } }
}

struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Text("设置").font(.system(size: 20, weight: .semibold)).padding(.horizontal, 12)
                VStack(spacing: 6) {
                    ForEach(SettingsPane.allCases) { pane in
                        Button { selection = pane } label: {
                            HStack(spacing: 12) {
                                Image(systemName: pane.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 28, height: 28)
                                    .background(selection == pane ? WorkbenchStyle.selection : WorkbenchStyle.surface,
                                                in: RoundedRectangle(cornerRadius: 7))
                                Text(LocalizedStringKey(pane.title)).font(.system(size: 13, weight: .medium))
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(selection == pane ? Color.white.opacity(0.06) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(WorkbenchHoverButtonStyle())
                        .accessibilityAddTraits(selection == pane ? [.isSelected] : [])
                    }
                }
                Spacer()
                Text("MyGit").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            .padding(16).padding(.top, 12)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(WorkbenchStyle.sidebar)
            Rectangle().fill(WorkbenchStyle.border).frame(width: 1)
            Group {
                switch selection {
                case .general: GeneralSettingsView()
                case .commit: CommitSettingsView()
                case .updates: UpdateSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 960, maxWidth: .infinity,
               minHeight: 620, idealHeight: 760, maxHeight: .infinity)
        .background(WorkbenchStyle.background)
        .preferredColorScheme(.dark)
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).font(.system(size: 26, weight: .semibold))
            Text(LocalizedStringKey(subtitle)).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .semibold))
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkbenchStyle.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkbenchStyle.border.opacity(0.7)))
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.current
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(title: "通用", subtitle: "调整 MyGit 的语言和阅读体验。")
                SettingsCard(title: "语言") {
                    HStack(alignment: .center) {
                        Text("语言修改将在重启应用后生效。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        WorkbenchPicker(title: "语言", values: AppLanguage.allCases, selection: $language) { $0.name }
                        .frame(width: 150)
                        .onChange(of: language) { _, value in value.save() }
                    }
                }
                SettingsCard(title: "应用字体大小") {
                    Text("调整侧边栏、列表和 diff 的字体大小，立即应用于所有窗口。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Text("10").foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: AppTypography.fontSizeRange, step: 1)
                            .accessibilityLabel(Text("应用字体大小"))
                        Text("18").foregroundStyle(.secondary)
                        Text(verbatim: "\(Int(fontSize)) pt")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .frame(width: 60, height: 32)
                            .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 6))
                    }
                    HStack {
                        Spacer()
                        Button("恢复默认字号") { fontSize = AppTypography.defaultFontSize }
                            .disabled(fontSize == AppTypography.defaultFontSize)
                    }
                }
                SettingsCard(title: "预览") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("工作树与提交记录", systemImage: "point.3.connected.trianglepath.dotted")
                            .appFont(size: 12, weight: .semibold)
                        Text("Repository · main").appFont(size: 10).foregroundStyle(.secondary)
                        Divider()
                        Text("+ let fontSize = 12").appFont(size: 12, design: .monospaced).foregroundStyle(.green)
                        Text("  // MyGit").appFont(size: 12, design: .monospaced).foregroundStyle(.secondary)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: 820).padding(32).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(WorkbenchButtonStyle())
    }
}

// Own the native settings window so changing SwiftUI panes cannot replace its resize bounds.
@MainActor final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.title = AppLocalization.text("MyGit 设置")
        window.contentMinSize = NSSize(width: 820, height: 620)
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("MyGit.Settings") { window.center() }
        window.setFrameAutosaveName("MyGit.Settings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { return nil }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
