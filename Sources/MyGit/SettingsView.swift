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

struct SettingsView: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.current
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("语言", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.name).tag(language)
                        }
                    }
                    .onChange(of: language) { _, value in value.save() }
                    Text("语言修改将在重启应用后生效。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("应用字体大小", selection: $fontSize) {
                        ForEach(10...18, id: \.self) { size in
                            Text("\(size) pt").tag(Double(size))
                        }
                    }
                    Text("调整侧边栏、列表和 diff 的字体大小，立即应用于所有窗口。")
                        .foregroundStyle(.secondary)
                }
                Section("预览") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("工作树与提交记录").appFont(size: 12, weight: .semibold)
                        Text("Repository · main").appFont(size: 10)
                            .foregroundStyle(.secondary)
                        Text("+ let fontSize = 12").appFont(size: 12, design: .monospaced)
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 6)
                }
                Button("恢复默认字号") { fontSize = AppTypography.defaultFontSize }
                    .disabled(fontSize == AppTypography.defaultFontSize)
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 460)
        .preferredColorScheme(.dark)
    }
}
