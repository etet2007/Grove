import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let preferenceKey = "appLanguage"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    static var current: AppLanguage {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return language.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    // macOS reads AppleLanguages at launch, including for its standard app menus.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
        defaults.set([rawValue], forKey: "AppleLanguages")
    }
}

enum AppLocalization {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
