import XCTest
import CoreGraphics
@testable import LyrinotchCore

final class IslandVisualGeometryTests: XCTestCase {
    private let sampleNotch = CGSize(width: 185, height: 32)

    func testExpandedBodyHeightAccountsForScrubberTimeRow() {
        XCTAssertEqual(IslandVisualGeometry.expandedBodyHeight(showAdjacentLines: false), 200)
        XCTAssertEqual(IslandVisualGeometry.expandedBodyHeight(showAdjacentLines: true), 232)
        XCTAssertGreaterThan(
            IslandVisualGeometry.expandedBodyHeight(showAdjacentLines: true),
            IslandVisualGeometry.expandedBodyHeight(showAdjacentLines: false)
        )
    }

    func testExpandedBodyOnlyReservesTranslationSpaceWhenNeeded() {
        let compact = IslandVisualGeometry.expandedBodyHeight(showAdjacentLines: true)
        let translated = IslandVisualGeometry.expandedBodyHeight(
            showAdjacentLines: true,
            hasTranslation: true
        )

        XCTAssertEqual(translated - compact, 40, accuracy: 0.5)
    }

    func testNotchCollapsedWidthIncludesWingsAndExtra() {
        let base = IslandVisualGeometry.closedNotchTotalWidth(
            deviceNotch: sampleNotch,
            islandExtraWidth: 0
        )
        let wide = IslandVisualGeometry.closedNotchTotalWidth(
            deviceNotch: sampleNotch,
            islandExtraWidth: 48
        )
        XCTAssertGreaterThan(base, sampleNotch.width)
        XCTAssertEqual(wide - base, 48, accuracy: 0.5)
    }

    func testNotchOpenedWidthIncludesExtraAndCapsAtMax() {
        let opened = IslandVisualGeometry.openedNotchWidth(
            deviceNotch: sampleNotch,
            islandExtraWidth: 0
        )
        let withExtra = IslandVisualGeometry.openedNotchWidth(
            deviceNotch: sampleNotch,
            islandExtraWidth: 120
        )
        XCTAssertGreaterThanOrEqual(opened, 460)
        XCTAssertLessThanOrEqual(opened, IslandVisualGeometry.maxExpandedWidth)
        XCTAssertEqual(withExtra, opened + 120, accuracy: 0.5)
        XCTAssertLessThanOrEqual(withExtra, IslandVisualGeometry.maxExpandedWidth)
    }

    func testHitSizeMatchesExtraWidthForExpandedNotch() {
        let zero = IslandVisualGeometry.visualSize(
            presentation: .notchIsland,
            mode: .expanded,
            deviceNotch: sampleNotch,
            islandExtraWidth: 0,
            showAdjacentLines: true
        )
        let wide = IslandVisualGeometry.visualSize(
            presentation: .notchIsland,
            mode: .expanded,
            deviceNotch: sampleNotch,
            islandExtraWidth: 60,
            showAdjacentLines: true
        )
        XCTAssertEqual(wide.width - zero.width, 60, accuracy: 0.5)
        // Housing + compact expanded body (adjacent, no translation).
        XCTAssertEqual(
            zero.height,
            IslandVisualGeometry.closedNotchHeight(deviceNotch: sampleNotch) + 232,
            accuracy: 0.5
        )
    }

    func testContentSizeIsAtLeastExpandedVisual() {
        let visual = IslandVisualGeometry.visualSize(
            presentation: .notchIsland,
            mode: .expanded,
            deviceNotch: sampleNotch,
            islandExtraWidth: 40,
            showAdjacentLines: true
        )
        let canvas = IslandVisualGeometry.contentSize(
            presentation: .notchIsland,
            deviceNotch: sampleNotch,
            islandExtraWidth: 40,
            showAdjacentLines: true
        )
        XCTAssertGreaterThanOrEqual(canvas.width, visual.width)
        XCTAssertGreaterThanOrEqual(canvas.height, visual.height)
    }

    func testFloatingExpandedWidthIncludesExtra() {
        let w = IslandVisualGeometry.floatingExpandedWidth(islandExtraWidth: 30)
        XCTAssertEqual(w, 560 + 30, accuracy: 0.5)
    }
}
