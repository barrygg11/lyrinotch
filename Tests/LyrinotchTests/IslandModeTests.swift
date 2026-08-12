import XCTest
@testable import LyrinotchCore

final class IslandModeTests: XCTestCase {
    func testDisplayNames() {
        L10n.current = .traditionalChinese
        XCTAssertEqual(IslandMode.collapsed.displayNameZH, "收合")
        XCTAssertEqual(IslandMode.expanded.displayNameZH, "展開")
        XCTAssertEqual(OverlayPresentationStyle.notchIsland.displayNameZH, "動態島")

        L10n.current = .english
        XCTAssertEqual(IslandMode.collapsed.localizedName, "Collapsed")
        XCTAssertEqual(IslandMode.expanded.localizedName, "Expanded")
        L10n.current = .traditionalChinese
    }

    func testPreferExpandedDefaultOff() {
        XCTAssertFalse(AppPreferences.default.preferExpanded)
        XCTAssertTrue(AppPreferences.default.expandOnTrackChange)
        XCTAssertEqual(AppPreferences.default.preferredLanguage, .system)
    }
}
