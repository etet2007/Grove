import SwiftUI

struct AppIconSettingsView: View {
    @ObservedObject private var controller = AppIconController.shared
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @FocusState private var focusedIcon: AppIcon?
    @State private var keyboardScrollTarget: AppIcon?
    @State private var gridWidth: CGFloat = 0

    private var scale: CGFloat { AppTypography.scale(for: fontSize) }
    private var columnCount: Int { max(1, Int((gridWidth + 12) / (140 * scale + 12))) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsPageHeader(title: "应用图标", subtitle: "为 Grove 选择一棵喜欢的树。")
                    HStack(spacing: 16) {
                        artwork(controller.selected, size: 64 * scale)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(controller.selected.title)).appFont(size: 16, weight: .semibold)
                            Text("立即更新 Dock 和应用切换器，重启后保留。")
                                .appFont(size: 12).foregroundStyle(.secondary)
                            Text("Finder 中的应用文件仍使用默认图标。")
                                .appFont(size: 11).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    if let error = controller.errorMessage {
                        Text(error).appFont(size: 12).foregroundStyle(.red)
                    }
                    iconGroup("通用", icons: [.vectorGreen, .glassGreen, .mutedGreen, .folded, .sculpted])
                    iconGroup("四季", icons: [.spring, .summer, .autumn, .winter])
                    Button("恢复默认图标") { controller.select(.vectorGreen) }
                        .buttonStyle(WorkbenchButtonStyle())
                        .disabled(controller.selected == .vectorGreen)
                }
                .frame(maxWidth: 820).padding(32).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Mouse-down can focus a button before mouse-up activates it. Moving
            // that button here would move its hit target out from under the pointer.
            // Only explicit keyboard navigation requests scrolling.
            .onChange(of: keyboardScrollTarget) { _, icon in
                if let icon { proxy.scrollTo(icon, anchor: .center) }
            }
        }
    }

    private func iconGroup(_ title: String, icons: [AppIcon]) -> some View {
        SettingsCard(title: title) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 12) {
                ForEach(icons) { icon in
                    Button {
                        controller.select(icon)
                        focusedIcon = icon
                        keyboardScrollTarget = nil
                    } label: {
                        VStack(spacing: 8) {
                            artwork(icon, size: 88 * scale)
                            HStack(spacing: 5) {
                                Text(LocalizedStringKey(icon.title)).lineLimit(1)
                                if !icon.reference.isEmpty {
                                    Text(verbatim: icon.reference).foregroundStyle(.secondary)
                                }
                            }
                            .appFont(size: 12, weight: .medium)
                            Image(systemName: controller.selected == icon ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(controller.selected == icon ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                                .appFont(size: 13)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(WorkbenchChoiceCardStyle(isSelected: controller.selected == icon, isFocused: focusedIcon == icon))
                    .focusable()
                    .focused($focusedIcon, equals: icon)
                    .focusEffectDisabled()
                    .id(icon)
                    .help(AppLocalization.text(icon.title))
                    .accessibilityLabel(Text(LocalizedStringKey(icon.title)))
                    .accessibilityAddTraits(controller.selected == icon ? [.isSelected] : [])
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { event in
                        moveFocus(from: icon, key: event.key)
                        return .handled
                    }
                    .onKeyPress(.return) { controller.select(icon); return .handled }
                    .onKeyPress(.space) { controller.select(icon); return .handled }
                    .onKeyPress(.escape) { focusedIcon = nil; return .handled }
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { gridWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in gridWidth = width }
                }
            }
        }
    }

    private func moveFocus(from icon: AppIcon, key: KeyEquivalent) {
        let groups: [[AppIcon]] = [[.vectorGreen, .glassGreen, .mutedGreen, .folded, .sculpted], [.spring, .summer, .autumn, .winter]]
        let catalog = groups.flatMap { $0 }
        if key == .leftArrow || key == .rightArrow {
            guard let index = catalog.firstIndex(of: icon) else { return }
            focusedIcon = catalog[min(catalog.count - 1, max(0, index + (key == .leftArrow ? -1 : 1)))]
        } else {
            // Preserve the visual column when crossing a section with a partial row.
            let rows = groups.flatMap { group in
                stride(from: 0, to: group.count, by: columnCount).map {
                    Array(group[$0..<min(group.count, $0 + columnCount)])
                }
            }
            guard let row = rows.firstIndex(where: { $0.contains(icon) }),
                  let column = rows[row].firstIndex(of: icon) else { return }
            let next = rows[min(rows.count - 1, max(0, row + (key == .upArrow ? -1 : 1)))]
            focusedIcon = next[min(column, next.count - 1)]
        }
        keyboardScrollTarget = focusedIcon
    }

    @ViewBuilder private func artwork(_ icon: AppIcon, size: CGFloat) -> some View {
        if let image = icon.image {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "tree").frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
