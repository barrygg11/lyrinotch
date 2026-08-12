import XCTest
@testable import LyrinotchCore

final class NotchOverlayLyricsAvailabilityTests: XCTestCase {
    @MainActor
    func testPlainTimelineCanDisplayWithoutBeingPromotedToSynced() {
        XCTAssertTrue(NotchOverlayView.supportsTimelineDisplay(.plain))
        XCTAssertTrue(NotchOverlayView.supportsTimelineDisplay(.synced))
        XCTAssertFalse(NotchOverlayView.supportsTimelineDisplay(.instrumental))
        XCTAssertFalse(NotchOverlayView.supportsTimelineDisplay(.notFound))
    }
}
