import XCTest
@testable import LyrinotchCore

final class OverlayAppearanceTests: XCTestCase {
    func testClampsOpacityAndFontSize() {
        let low = OverlayAppearance(opacity: 0.01, fontSize: 1)
        XCTAssertEqual(low.opacity, 0.2, accuracy: 0.0001)
        XCTAssertEqual(low.fontSize, 12, accuracy: 0.0001)

        let high = OverlayAppearance(opacity: 2, fontSize: 99)
        XCTAssertEqual(high.opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(high.fontSize, 24, accuracy: 0.0001)
    }

    func testIslandHUDDefaults() {
        let d = OverlayAppearance.default
        XCTAssertEqual(d.opacity, 0.88, accuracy: 0.001)
        XCTAssertEqual(d.fontSize, 15, accuracy: 0.001)
        XCTAssertFalse(d.showTrackTitle)
        XCTAssertFalse(d.showAdjacentLines)
        XCTAssertTrue(d.clickThrough)
        XCTAssertFalse(d.liquidGlassOnNotch)
        XCTAssertFalse(d.liquidGlassOnFloating)
        XCTAssertFalse(d.usesLiquidGlassAnywhere)
        XCTAssertFalse(d.usesLiquidGlass(for: .notchIsland))
        XCTAssertFalse(d.usesLiquidGlass(for: .floatingHUD))
        XCTAssertEqual(d.glassVariant, .tinted)
    }

    func testLiquidGlassPerPresentation() {
        var d = OverlayAppearance.default
        d.liquidGlassOnNotch = true
        XCTAssertTrue(d.usesLiquidGlass(for: .notchIsland))
        XCTAssertFalse(d.usesLiquidGlass(for: .floatingHUD))
        d.liquidGlassOnFloating = true
        XCTAssertTrue(d.usesLiquidGlassAnywhere)
    }

    func testDefaultVerticalOffsetFlushToNotch() {
        XCTAssertEqual(AppPreferences.default.verticalOffset, 0, accuracy: 0.001)
    }
}
