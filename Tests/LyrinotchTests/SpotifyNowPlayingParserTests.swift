import XCTest
@testable import LyrinotchCore

final class SpotifyNowPlayingParserTests: XCTestCase {
    private let sep = SpotifyAppleScript.fieldSeparator

    func testNotRunning() {
        let snap = SpotifyNowPlayingParser.parse("NOT_RUNNING")
        XCTAssertEqual(snap.availability, .playerNotRunning)
        XCTAssertEqual(snap.source, .spotify)
        XCTAssertEqual(snap.track, .empty)
    }

    func testStopped() {
        let snap = SpotifyNowPlayingParser.parse("STOPPED")
        XCTAssertEqual(snap.availability, .noTrack)
    }

    func testErrorPayload() {
        let snap = SpotifyNowPlayingParser.parse("ERROR\(sep)permission denied")
        XCTAssertEqual(snap.availability, .error)
        XCTAssertEqual(snap.detail, "permission denied")
    }

    func testReadyPlaying() {
        let raw = [
            "OK",
            "playing",
            "spotify:track:abc",
            "Some Song",
            "Some Artist",
            "Some Album",
            "163000",
            "12.5",
            "1786410000.125"
        ].joined(separator: sep)

        let snap = SpotifyNowPlayingParser.parse(raw)
        XCTAssertEqual(snap.availability, .ready)
        XCTAssertEqual(snap.track.id, "spotify:track:abc")
        XCTAssertEqual(snap.track.name, "Some Song")
        XCTAssertEqual(snap.track.artist, "Some Artist")
        XCTAssertEqual(snap.track.album, "Some Album")
        XCTAssertEqual(snap.track.duration ?? -1, 163, accuracy: 0.001)
        XCTAssertEqual(snap.track.position ?? -1, 12.5, accuracy: 0.001)
        XCTAssertEqual(
            snap.track.positionSampledAt?.timeIntervalSince1970 ?? -1,
            1_786_410_000.125,
            accuracy: 0.001
        )
        XCTAssertTrue(snap.track.isPlaying)
        XCTAssertEqual(snap.track.displayTitle, "Some Artist — Some Song")
    }

    func testReadyPaused() {
        let raw = [
            "OK",
            "paused",
            "spotify:track:xyz",
            "Ballad",
            "Singer",
            "",
            "60000",
            "3"
        ].joined(separator: sep)

        let snap = SpotifyNowPlayingParser.parse(raw)
        XCTAssertEqual(snap.availability, .ready)
        XCTAssertFalse(snap.track.isPlaying)
        XCTAssertNil(snap.track.album)
        XCTAssertEqual(snap.track.duration ?? -1, 60, accuracy: 0.001)
        XCTAssertNil(snap.track.positionSampledAt)
    }

    func testTitleWithSpecialCharactersStillParses() {
        let raw = [
            "OK",
            "playing",
            "spotify:track:1",
            "A|B — C",
            "DJ / feat. X",
            "Album (Live)",
            "120000",
            "1.25"
        ].joined(separator: sep)

        let snap = SpotifyNowPlayingParser.parse(raw)
        XCTAssertEqual(snap.availability, .ready)
        XCTAssertEqual(snap.track.name, "A|B — C")
        XCTAssertEqual(snap.track.artist, "DJ / feat. X")
    }

    func testUnrecognizedPayload() {
        let snap = SpotifyNowPlayingParser.parse("WTF something")
        XCTAssertEqual(snap.availability, .error)
    }

    func testEmptyPayload() {
        let snap = SpotifyNowPlayingParser.parse("   ")
        XCTAssertEqual(snap.availability, .error)
    }
}
