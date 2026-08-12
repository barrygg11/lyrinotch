import XCTest
import CoreGraphics
@testable import LyrinotchCore

final class NotchGeometryLogicTests: XCTestCase {
    /// Values captured from a 14" M-series Built-in Retina Display probe.
    func testHardwareNotchFromAuxiliaryAreas() {
        let screen = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let left = CGRect(x: -1512, y: 950, width: 663, height: 32)
        let right = CGRect(x: -664, y: 950, width: 664, height: 32)

        let band = NotchGeometryLogic.band(
            screenFrame: screen,
            auxiliaryTopLeft: left,
            auxiliaryTopRight: right,
            safeAreaTop: 32
        )

        XCTAssertNotNil(band)
        XCTAssertEqual(band?.isHardwareNotch, true)
        XCTAssertEqual(band?.frame.width ?? 0, 185, accuracy: 0.5)
        XCTAssertEqual(band?.frame.midX ?? 0, -756.5, accuracy: 0.5)
        XCTAssertEqual(band?.frame.minX ?? 0, -849, accuracy: 0.5)
        XCTAssertEqual(band?.frame.maxX ?? 0, -664, accuracy: 0.5)
        // Collapsed island should be a bit wider than the camera housing.
        XCTAssertEqual(band?.preferredCollapsedWidth ?? 0, 221, accuracy: 0.5)
    }

    func testExternalDisplayWithoutNotch() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let band = NotchGeometryLogic.band(
            screenFrame: screen,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            safeAreaTop: 0
        )
        XCTAssertNil(band)
    }

    func testSafeAreaFallbackCentered() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let band = NotchGeometryLogic.band(
            screenFrame: screen,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            safeAreaTop: 32
        )
        XCTAssertNotNil(band)
        XCTAssertEqual(band?.isHardwareNotch, false)
        XCTAssertEqual(band?.frame.midX ?? 0, screen.midX, accuracy: 0.5)
    }
}
