import XCTest
@testable import LyrinotchCore

final class LocalizationParityTests: XCTestCase {
    func testEverySupportedLanguageHasTheSameKeys() {
        let expected = Set(L10n.zhHant.keys)

        XCTAssertEqual(Set(L10n.zhHans.keys), expected)
        XCTAssertEqual(Set(L10n.en.keys), expected)
        XCTAssertEqual(Set(L10n.ja.keys), expected)
    }

    func testSettingsInformationArchitectureKeysExist() {
        let keys = [
            "tab.general",
            "tab.display",
            "tab.lyrics",
            "tab.appearance",
            "tab.system",
            "section.track_calibration",
            "section.appearance_preview",
            "button.reset_layout",
            "settings.current_version"
        ]

        for key in keys {
            XCTAssertNotNil(L10n.zhHant[key], "Missing Traditional Chinese key: \(key)")
        }
    }
}
