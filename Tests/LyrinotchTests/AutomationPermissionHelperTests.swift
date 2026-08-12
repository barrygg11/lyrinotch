import XCTest
@testable import LyrinotchCore

final class AutomationPermissionHelperTests: XCTestCase {
    /// Must finish quickly and never crash (System tab depends on this).
    func testStatusDoesNotHangOrCrash() {
        let exp = expectation(description: "status probe")
        DispatchQueue.global().async {
            let musicStatus = AutomationPermissionHelper.status(for: .appleMusic)
            let spotifyStatus = AutomationPermissionHelper.status(for: .spotify)
            XCTAssertNotNil(musicStatus)
            XCTAssertNotNil(spotifyStatus)
            exp.fulfill()
        }
        // Soft probe has ~1.2s timeout per target; allow headroom.
        wait(for: [exp], timeout: 5.0)
    }

    func testTargetDisplayNames() {
        XCTAssertEqual(TargetPlayerApp.appleMusic.displayName, "Apple Music")
        XCTAssertEqual(TargetPlayerApp.spotify.displayName, "Spotify")
        XCTAssertEqual(TargetPlayerApp.appleMusic.rawValue, "com.apple.Music")
        XCTAssertEqual(TargetPlayerApp.spotify.rawValue, "com.spotify.client")
    }

    func testPassiveProbeNeverTreatsPlayerLivenessAsAuthorization() {
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeOutput: "PLAYER_RUNNING",
                askUserFacing: false
            ),
            .unknown
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeOutput: "NOT_RUNNING",
                askUserFacing: false
            ),
            .playerNotRunning
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(fromProbeOutput: "OK", askUserFacing: false),
            .unknown
        )
    }

    func testExplicitProbeMapsAuthorizationAndDenial() {
        XCTAssertEqual(
            AutomationPermissionHelper.status(fromProbeOutput: "OK", askUserFacing: true),
            .authorized
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeOutput: "ERR:-1743:Not authorized to send Apple events",
                askUserFacing: true
            ),
            .denied
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeOutput: "ERR:-1744:Sending this event would require user consent",
                askUserFacing: true
            ),
            .notDetermined
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeOutput: "ERR:-600:Application isn’t running",
                askUserFacing: true
            ),
            .playerNotRunning
        )
    }

    func testExplicitProbeDistinguishesTimeoutFromUnknownFailure() {
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeResult: .timedOut,
                askUserFacing: true
            ),
            .timedOut
        )
        XCTAssertEqual(
            AutomationPermissionHelper.status(
                fromProbeResult: .output("unexpected failure"),
                askUserFacing: true
            ),
            .unknown
        )
    }
}
