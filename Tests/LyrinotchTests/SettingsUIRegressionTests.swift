import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class SettingsUIRegressionTests: XCTestCase {
    func testFiveSettingsTabsKeepProfessionalLocalizedTitles() {
        XCTAssertEqual(
            SettingsTab.allCases.map(\.titleKey),
            ["tab.general", "tab.display", "tab.lyrics", "tab.appearance", "tab.system"]
        )
        XCTAssertEqual(L10n.en["tab.appearance"], "Appearance")
        XCTAssertEqual(L10n.ja["tab.system"], "プレイヤー")
    }

    func testSpecificPickerIdentityIgnoresLegacyDisplayLabel() {
        XCTAssertEqual(
            ScreenPickerSelection(.specific(displayID: 42, displayName: "Mi Monitor · 主畫面")),
            .specific(displayID: 42)
        )
    }

    @MainActor
    func testIdleMenuTrackTitleUsesActiveLanguage() {
        let previousLanguage = L10n.current
        defer { L10n.apply(previousLanguage) }

        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        model.nowPlaying = .playerNotRunning

        model.setPreferredLanguage(.traditionalChinese)
        XCTAssertEqual(model.menuTrackTitle, "目前沒有播放")
        model.setPreferredLanguage(.simplifiedChinese)
        XCTAssertEqual(model.menuTrackTitle, "当前没有播放")
        model.setPreferredLanguage(.english)
        XCTAssertEqual(model.menuTrackTitle, "Nothing playing")
        model.setPreferredLanguage(.japanese)
        XCTAssertEqual(model.menuTrackTitle, "再生中の曲はありません")
    }
}
