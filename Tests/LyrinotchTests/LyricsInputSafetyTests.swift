import XCTest
@testable import LyrinotchCore

final class LyricsInputSafetyTests: XCTestCase {
    func testSearchHitSubtitleDoesNotConvertUnrepresentableDuration() {
        let hit = LyricsSearchHit(
            id: "malformed",
            trackName: "Song",
            artistName: "Artist",
            duration: 1e300,
            hasSynced: true,
            sourceLabel: "test",
            snapshot: LyricsSnapshot(availability: .synced)
        )

        XCTAssertEqual(hit.subtitle, "Artist · test · LRC")
    }

    func testTrackIdentityTreatsUnrealisticDurationAsUnknown() {
        let track = Track(
            id: nil,
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 1e300,
            position: nil,
            isPlaying: true
        )

        let identity = TrackIdentity(track: track, source: .spotify)
        XCTAssertTrue(identity.storageKey.hasSuffix(":-"))
    }
}
