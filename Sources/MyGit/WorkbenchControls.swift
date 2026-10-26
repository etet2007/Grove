import SwiftUI

enum WorkbenchStyle {
    static let background = Color(red: 37 / 255, green: 38 / 255, blue: 38 / 255)
    static let sidebar = Color(red: 33 / 255, green: 33 / 255, blue: 33 / 255)
    static let surface = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)
    static let raised = Color(red: 54 / 255, green: 55 / 255, blue: 55 / 255)
    static let border = Color(red: 57 / 255, green: 58 / 255, blue: 58 / 255)
    static let accent = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let selection = Color(red: 0.008, green: 0.518, blue: 0.78)
    static let muted = Color(red: 0.63, green: 0.63, blue: 0.67)

    // Shared input/select tokens. Keep neutral surfaces distinct from diff/status colors.
    static let control = Color(red: 43 / 255, green: 44 / 255, blue: 44 / 255)
    static let controlBorder = Color(red: 72 / 255, green: 73 / 255, blue: 73 / 255)
    static let controlRadius: CGFloat = 6
    static let controlInset: CGFloat = 10

    static func repositoryColor(_ name: String) -> Color {
        let palette: [Color] = [accent, .orange, .green, .purple, .pink, .yellow]
        let hash = name.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    static func committerColor(_ name: String) -> Color {
        // Use a stable hash so colors survive app restarts and list reordering.
        let hash = name.utf8.reduce(UInt64(14695981039346656037)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let hue = Double(hash % 3600) / 3600
        return Color(hue: hue, saturation: 0.65, brightness: 0.95)
    }
}

private struct WorkbenchHoverFeedback: ViewModifier {
    var isPressed = false
    var enabled = true
    var cornerRadius: CGFloat = 5
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(isEnabled && enabled ? (isPressed ? 0.12 : isHovered ? 0.06 : 0) : 0))
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
    }
}

extension View {
    func workbenchHoverFeedback(enabled: Bool = true, cornerRadius: CGFloat = 5) -> some View {
        modifier(WorkbenchHoverFeedback(enabled: enabled, cornerRadius: cornerRadius))
    }
}

struct WorkbenchHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .modifier(WorkbenchHoverFeedback(isPressed: configuration.isPressed))
    }
}

struct WorkbenchRowButtonStyle: ButtonStyle {
    var isSelected = false
    var verticalPadding: CGFloat = 5

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Row(label: configuration.label, isSelected: isSelected, isPressed: configuration.isPressed, verticalPadding: verticalPadding)
    }

    private struct Row: View {
        let label: ButtonStyleConfiguration.Label
        let isSelected: Bool
        let isPressed: Bool
        let verticalPadding: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            label
                .padding(.vertical, verticalPadding).padding(.horizontal, 6)
                .background(isSelected ? WorkbenchStyle.selection
                            : isEnabled && isPressed ? WorkbenchStyle.raised
                            : isEnabled && isHovered ? WorkbenchStyle.surface : Color.clear)
                .overlay {
                    if isEnabled && isSelected && (isHovered || isPressed) {
                        Color.white.opacity(isPressed ? 0.16 : 0.08)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

struct WorkbenchButtonStyle: ButtonStyle {
    var emphasized = false
    var size: WorkbenchControlSize = .small
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .appFont(size: 12, weight: .medium)
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: size.height * AppTypography.scale(for: fontSize))
            .background(emphasized ? WorkbenchStyle.selection.opacity(configuration.isPressed ? 0.75 : 1)
                                  : WorkbenchStyle.surface.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius)
                .strokeBorder(emphasized ? WorkbenchStyle.accent.opacity(0.32) : WorkbenchStyle.border.opacity(0.65)))
            .opacity(isEnabled ? 1 : 0.4)
            .modifier(WorkbenchHoverFeedback(isPressed: configuration.isPressed, cornerRadius: WorkbenchStyle.controlRadius))
    }
}

enum WorkbenchControlSize {
    case small, compact, regular
    var height: CGFloat {
        switch self {
        case .small: 28
        case .compact: 32
        case .regular: 36
        }
    }
}

/// A single surface for fields and select triggers, including keyboard focus and disabled states.
struct WorkbenchControlSurface: ViewModifier {
    var isFocused = false
    var isPressed = false
    var size: WorkbenchControlSize = .compact
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .appFont(size: 12)
            .padding(.horizontal, WorkbenchStyle.controlInset)
            .frame(height: size.height * AppTypography.scale(for: fontSize))
            .background(isEnabled && (isHovered || isPressed) ? WorkbenchStyle.surface : WorkbenchStyle.control,
                        in: RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius)
                    .strokeBorder(isEnabled && isFocused ? WorkbenchStyle.accent.opacity(0.8)
                                  : WorkbenchStyle.controlBorder.opacity(isEnabled ? (isHovered ? 1 : 0.7) : 0.4))
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { isHovered = $0 }
    }
}

struct WorkbenchTextField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var autofocus = false
    var size: WorkbenchControlSize = .regular
    var allowsClear = false
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(isFocused ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                    .accessibilityHidden(true)
                    .onTapGesture { if isEnabled { isFocused = true } }
            }
            TextField(LocalizedStringKey(title), text: $text,
                      prompt: Text(LocalizedStringKey(title)).foregroundColor(WorkbenchStyle.muted))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel(Text(LocalizedStringKey(title)))
                .layoutPriority(1)
            if allowsClear {
                Button { text = ""; isFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WorkbenchStyle.muted)
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorkbenchHoverButtonStyle())
                .help(AppLocalization.text("清除搜索"))
                .accessibilityLabel(AppLocalization.text("清除搜索"))
                .opacity(text.isEmpty ? 0 : 1)
                .disabled(text.isEmpty || !isEnabled)
                .accessibilityHidden(text.isEmpty)
            }
        }
        .modifier(WorkbenchControlSurface(isFocused: isFocused, size: size))
        .task {
            guard autofocus else { return }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, isEnabled else { return }
            isFocused = true
        }
    }
}

struct WorkbenchSearchField: View {
    let title: String
    @Binding var text: String
    var autofocus = false

    var body: some View {
        WorkbenchTextField(title: title, text: $text, icon: "magnifyingglass",
                           autofocus: autofocus, size: .compact, allowsClear: true)
    }
}

@MainActor private final class WorkbenchPickerFocus<Value: Hashable>: ObservableObject {
    @Published var value: Value?
}

/// Value selectors use the same trigger and opaque, scrollable option list throughout the app.
struct WorkbenchPicker<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var size: WorkbenchControlSize = .compact
    var menuWidth: CGFloat = 220
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(AppTypography.fontSizeKey) private var fontSize = AppTypography.defaultFontSize
    @State private var isPresented = false
    @FocusState private var triggerFocused: Bool
    @StateObject private var keyboardFocus = WorkbenchPickerFocus<Value>()

    private var preferredLabelWidth: CGFloat {
        let scale = AppTypography.scale(for: fontSize)
        let font = NSFont.systemFont(ofSize: 12 * scale)
        return min(180 * scale, values.map { (label($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
    }

    var body: some View {
        Button { if isPresented { isPresented = false } else { openPicker() } } label: {
            HStack(spacing: 10) {
                Text(label(selection)).lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, idealWidth: preferredLabelWidth, maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .appFont(size: 10, weight: .medium)
                    .foregroundStyle(WorkbenchStyle.muted)
            }
            .modifier(WorkbenchControlSurface(isFocused: triggerFocused || isPresented, isPressed: isPresented, size: size))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(values.isEmpty)
        .focusable().focused($triggerFocused).focusEffectDisabled()
        .accessibilityLabel(AppLocalization.text(title))
        .accessibilityValue(label(selection))
        .help(AppLocalization.text(title) + " · " + label(selection))
        .onKeyPress(.downArrow) { openPicker(); return .handled }
        .onKeyPress(.space) { openPicker(); return .handled }
        .onKeyPress(.return) { openPicker(); return .handled }
        .onChange(of: isEnabled) { _, enabled in if !enabled { isPresented = false } }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.text(title)).appFont(size: 11, weight: .medium)
                        .foregroundStyle(WorkbenchStyle.muted).padding(.horizontal, 8).padding(.top, 4)
                    Divider().padding(.horizontal, 8)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(values, id: \.self) { value in
                                Button { choose(value) } label: {
                                    HStack(spacing: 12) {
                                        Text(label(value)).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 8)
                                        Image(systemName: "checkmark")
                                            .appFont(size: 10, weight: .semibold)
                                            .foregroundStyle(WorkbenchStyle.accent)
                                            .opacity(value == selection ? 1 : 0)
                                    }
                                    .appFont(size: 12)
                                    .padding(.horizontal, 8)
                                    .frame(height: size.height * AppTypography.scale(for: fontSize))
                                    .background(value == selection || value == keyboardFocus.value ? WorkbenchStyle.surface : .clear,
                                                in: RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: WorkbenchStyle.controlRadius)
                                            .strokeBorder(value == keyboardFocus.value ? WorkbenchStyle.controlBorder : .clear)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(WorkbenchHoverButtonStyle())
                                .accessibilityAddTraits(value == selection ? [.isSelected] : [])
                                .help(label(value))
                                .id(value)
                            }
                        }.padding(4)
                    }
                    .frame(height: min(320, CGFloat(values.count) * (size.height * AppTypography.scale(for: fontSize) + 2) + 8))
                }
                .padding(6)
                .frame(width: menuWidth * AppTypography.scale(for: fontSize))
                .background(WorkbenchStyle.sidebar)
                .preferredColorScheme(.dark)
                .onAppear { proxy.scrollTo(selection) }
                .onChange(of: keyboardFocus.value) { _, value in if let value { proxy.scrollTo(value) } }
                .background {
                    WorkbenchPickerKeyboardInput(onMove: moveFocus,
                        onSelect: { choose(keyboardFocus.value ?? selection) },
                        onCancel: { isPresented = false; triggerFocused = true })
                }
            }
        }
    }

    private func openPicker() {
        guard isEnabled, !values.isEmpty else { return }
        keyboardFocus.value = selection
        isPresented = true
    }

    private func choose(_ value: Value) {
        guard isEnabled, values.contains(value) else { return }
        selection = value
        isPresented = false
        triggerFocused = true
    }

    private func moveFocus(_ direction: Int) {
        guard !values.isEmpty else { return }
        let index = keyboardFocus.value.flatMap { values.firstIndex(of: $0) } ?? 0
        keyboardFocus.value = values[min(max(0, index + direction), values.count - 1)]
    }
}

// A popover has its own AppKit window. Give that window a responder rather than
// relying on SwiftUI button focus, which can leave keystrokes in the source text field.
private struct WorkbenchPickerKeyboardInput: NSViewRepresentable {
    let onMove: (Int) -> Void
    let onSelect: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) {
        view.onMove = onMove; view.onSelect = onSelect; view.onCancel = onCancel
    }

    final class KeyView: NSView {
        var onMove: ((Int) -> Void)?
        var onSelect: (() -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        // This background responder owns keys only; option rows retain all mouse input.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeKey()
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onMove?(-1)
            case 125: onMove?(1)
            case 36, 76, 49: onSelect?()
            case 53: onCancel?()
            default: super.keyDown(with: event)
            }
        }
    }
}

struct WorkbenchSegments<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    Text(label(value))
                        .appFont(size: 11, weight: selection == value ? .semibold : .medium)
                        .foregroundStyle(selection == value ? WorkbenchStyle.accent : WorkbenchStyle.muted)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(selection == value ? WorkbenchStyle.surface : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(WorkbenchHoverButtonStyle())
                .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(WorkbenchStyle.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .fixedSize()
    }
}
