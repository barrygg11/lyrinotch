import XCTest
@testable import LyrinotchCore

final class AppLanguageTests: XCTestCase {
    func testUnsupportedSystemLanguagesFallBackToEnglish() {
        XCTAssertEqual(
            AppLanguage.detectSystemLanguage(preferredLanguages: ["ko-KR", "fr-FR"]),
            .english
        )
    }

    func testFirstSupportedPreferredLanguageWins() {
        XCTAssertEqual(
            AppLanguage.detectSystemLanguage(preferredLanguages: ["de-DE", "ja-JP", "en-US"]),
            .japanese
        )
        XCTAssertEqual(
            AppLanguage.detectSystemLanguage(preferredLanguages: ["zh-TW", "en-US"]),
            .traditionalChinese
        )
    }
}
