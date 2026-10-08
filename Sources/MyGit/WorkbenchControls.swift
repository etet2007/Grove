import SwiftUI

enum WorkbenchStyle {
    static let background = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let sidebar = Color(red: 0.094, green: 0.094, blue: 0.106)
    static let surface = Color(red: 0.149, green: 0.149, blue: 0.169)
    static let raised = Color(red: 0.165, green: 0.165, blue: 0.188)
    static let border = Color(red: 0.22, green: 0.22, blue: 0.245)
    static let accent = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let selection = Color(red: 0.008, green: 0.518, blue: 0.78)
    static let muted = Color(red: 0.63, green: 0.63, blue: 0.67)

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

struct WorkbenchButtonStyle: ButtonStyle {
    var emphasized = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .appFont(size: 12, weight: .medium)
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(emphasized ? WorkbenchStyle.selection.opacity(configuration.isPressed ? 0.75 : 1)
                                  : WorkbenchStyle.surface.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(emphasized ? WorkbenchStyle.accent.opacity(0.32) : WorkbenchStyle.border.opacity(0.65)))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct WorkbenchTextField: View {
    let title: String
    @Binding var text: String
    var icon: String? = nil
    var autofocus = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).foregroundStyle(WorkbenchStyle.muted)
            }
            TextField(LocalizedStringKey(title), text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .task {
                    guard autofocus else { return }
                    // Wait until the overlay is attached to the window before focusing.
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    isFocused = true
                }
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
        .appFont(size: 12)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(WorkbenchStyle.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isFocused ? WorkbenchStyle.accent.opacity(0.65) : WorkbenchStyle.border))
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
                .buttonStyle(.plain)
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
