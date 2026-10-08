import XCTest
@testable import MyGit

final class LocalizationTests: XCTestCase {
    func testLanguagePreferenceUpdatesLaunchLanguageAndSurvivesReload() throws {
        let suite = "MyGitLanguageTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppLanguage.simplifiedChinese.save(to: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["zh-Hans"])
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(reloaded.string(forKey: AppLanguage.preferenceKey), "zh-Hans")

        AppLanguage.english.save(to: defaults)
        XCTAssertEqual(reloaded.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertEqual(reloaded.string(forKey: AppLanguage.preferenceKey), "en")
    }
}
