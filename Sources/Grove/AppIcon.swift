import AppKit
import SwiftUI

enum AppIcon: String, CaseIterable, Identifiable {
    case vectorGreen = "vector-green"
    case glassGreen = "glass-green"
    case mutedGreen = "muted-green"
    case spring, summer, autumn, winter
    case folded = "folded-grove"
    case sculpted = "sculpted-grove"

    static let preferenceKey = "appIcon"
    private static let images = NSCache<NSString, NSImage>()
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vectorGreen: "经典绿"
        case .glassGreen: "玻璃绿"
        case .mutedGreen: "柔和绿"
        case .spring: "春 · 新芽"
        case .summer: "夏 · 繁荫"
        case .autumn: "秋 · 金叶"
        case .winter: "冬 · 霜林"
        case .folded: "折纸林"
        case .sculpted: "雕塑林"
        }
    }
    var reference: String {
        switch self {
        case .vectorGreen: "A"
        case .glassGreen: "B"
        case .mutedGreen: "A2"
        case .folded: "E"
        case .sculpted: "F"
        default: ""
        }
    }

    var image: NSImage? {
        let key = rawValue as NSString
        if let cached = Self.images.object(forKey: key) { return cached }
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png", subdirectory: "AppIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.images.setObject(image, forKey: key)
        return image
    }

    static func saved(in defaults: UserDefaults = .standard) -> AppIcon {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .vectorGreen
    }
}

@MainActor final class AppIconController: ObservableObject {
    static let shared = AppIconController()
    @Published private(set) var selected: AppIcon
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let loadImage: (AppIcon) -> NSImage?
    private let applyImage: @MainActor (NSImage) -> Void

    init(defaults: UserDefaults = .standard,
         loadImage: @escaping (AppIcon) -> NSImage? = { $0.image },
         applyImage: @escaping @MainActor (NSImage) -> Void = { NSApplication.shared.applicationIconImage = $0 }) {
        self.defaults = defaults
        self.loadImage = loadImage
        self.applyImage = applyImage
        selected = AppIcon.saved(in: defaults)
    }

    func restore() { select(selected) }

    func select(_ icon: AppIcon) {
        guard let image = loadImage(icon) else {
            errorMessage = AppLocalization.text("无法加载图标，请重新构建或安装 Grove。")
            return
        }
        applyImage(image)
        defaults.set(icon.rawValue, forKey: AppIcon.preferenceKey)
        selected = icon
        errorMessage = nil
    }
}
