import XCTest
@testable import LyrinotchCore

final class PreferencesStoreTests: XCTestCase {
    func testRoundTrip() {
        let store = PreferencesStore.ephemeral()
        var prefs = AppPreferences.default
        prefs.isOverlayVisible = false
        prefs.appearance = OverlayAppearance(
            opacity: 0.55,
            fontSize: 20,
            showTrackTitle: true,
            showAdjacentLines: true,
            clickThrough: false,
            liquidGlassOnNotch: true,
            liquidGlassOnFloating: true,
            glassVariant: .clear
        )
        prefs.screenPlacement = .specific(displayID: 42, displayName: "Studio Display")
        prefs.verticalOffset = 12
        prefs.launchAtLogin = true
        prefs.hotKeyEnabled = false
        prefs.preferExpanded = true
        prefs.expandOnTrackChange = false
        prefs.preferredLanguage = .japanese
        prefs.displayTraditionalChinese = false
        prefs.lyricOffsetSeconds = 1.5
        prefs.autoCalibrateLyricOffset = false
        prefs.hideInFullscreen = false
        prefs.lyricColorFromArtwork = false
        prefs.islandExtraWidth = 48
        prefs.lyricsSourcePreference = .netEaseFirst
        prefs.showTranslation = true
        prefs.translationTargetLanguage = "en"
        prefs.playerSelectionPreference = .appleMusic

        store.save(prefs)
        let loaded = store.load()

        XCTAssertEqual(loaded, prefs)
    }

    func testCorruptDataFallsBackToDefault() {
        let suiteName = "lyrinotch.tests.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data("not-json".utf8), forKey: "prefs")
        let store = PreferencesStore(defaults: defaults, key: "prefs")
        XCTAssertEqual(store.load(), .default)
    }

    func testLegacyPayloadUsesDefaultsForMissingFields() throws {
        let data = Data(#"{"isOverlayVisible":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertFalse(decoded.isOverlayVisible)
        XCTAssertEqual(decoded.appearance, .default)
        XCTAssertEqual(decoded.screenPlacement, .preferNotched)
        XCTAssertEqual(decoded.lyricsSourcePreference, .lrclibOnly)
        XCTAssertEqual(decoded.preferredLanguage, .system)
        XCTAssertFalse(decoded.autoCalibrateLyricOffset)
        XCTAssertEqual(decoded.playerSelectionPreference, .automatic)
    }

    func testVerticalOffsetClampedOnInit() {
        let high = AppPreferences(verticalOffset: 999)
        XCTAssertEqual(high.verticalOffset, 40, accuracy: 0.001)
        let low = AppPreferences(verticalOffset: -999)
        XCTAssertEqual(low.verticalOffset, -20, accuracy: 0.001)
    }

    func testLyricOffsetClampedOnInit() {
        let high = AppPreferences(lyricOffsetSeconds: 99)
        XCTAssertEqual(high.lyricOffsetSeconds, 5, accuracy: 0.001)
        let low = AppPreferences(lyricOffsetSeconds: -99)
        XCTAssertEqual(low.lyricOffsetSeconds, -5, accuracy: 0.001)
    }

    func testDisplayTraditionalDefaultTrue() {
        XCTAssertTrue(AppPreferences.default.displayTraditionalChinese)
    }

    func testAutoCalibrationDefaultsOff() {
        XCTAssertFalse(AppPreferences.default.autoCalibrateLyricOffset)
        XCTAssertFalse(AppPreferences().autoCalibrateLyricOffset)
    }

    func testLRCLIBOnlyIsDefaultAndSmartRemainsSelectable() throws {
        XCTAssertEqual(AppPreferences.default.lyricsSourcePreference, .lrclibOnly)
        XCTAssertEqual(
            LyricsSourcePreference.settingsCases,
            [.smartAutomatic, .lrclibOnly, .netEaseFirst, .maximumCoverage]
        )

        let explicitSmart = Data(#"{"lyricsSourcePreference":"smartAutomatic"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: explicitSmart)
        XCTAssertEqual(decoded.lyricsSourcePreference, .smartAutomatic)
    }

    func testScreenPlacementLegacyStringDecode() throws {
        // Older builds stored a bare string raw value.
        let data = Data(#""preferNotched""#.utf8)
        let placement = try JSONDecoder().decode(ScreenPlacement.self, from: data)
        XCTAssertEqual(placement, .preferNotched)

        let mouse = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#""mouseCursor""#.utf8))
        XCTAssertEqual(mouse, .mouseCursor)
    }

    func testScreenPlacementSpecificRoundTrip() throws {
        let original = ScreenPlacement.specific(displayID: 69_720, displayName: "Built-in Retina Display")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenPlacement.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
