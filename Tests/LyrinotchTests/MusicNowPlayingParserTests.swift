import XCTest
@testable import LyrinotchCore

final class MusicNowPlayingParserTests: XCTestCase {
    private let sep = MusicAppleScript.fieldSeparator

    func testNotRunning() {
        let snap = MusicNowPlayingParser.parse("NOT_RUNNING")
        XCTAssertEqual(snap.availability, .playerNotRunning)
        XCTAssertEqual(snap.source, .appleMusic)
    }

    func testStopped() {
        let snap = MusicNowPlayingParser.parse("STOPPED")
        XCTAssertEqual(snap.availability, .noTrack)
        XCTAssertEqual(snap.source, .appleMusic)
    }

    func testReadyPlayingDurationIsSeconds() {
        let raw = [
            "OK",
            "playing",
            "ABC123",
            "Song",
            "Artist",
            "Album",
            "210.5",
            "12.0",
            "1786410000.5"
        ].joined(separator: sep)

        let snap = MusicNowPlayingParser.parse(raw)
        XCTAssertEqual(snap.availability, .ready)
        XCTAssertEqual(snap.source, .appleMusic)
        XCTAssertEqual(snap.track.name, "Song")
        XCTAssertEqual(snap.track.artist, "Artist")
        XCTAssertEqual(snap.track.duration ?? -1, 210.5, accuracy: 0.01)
        XCTAssertEqual(snap.track.position ?? -1, 12.0, accuracy: 0.01)
        XCTAssertEqual(
            snap.track.positionSampledAt?.timeIntervalSince1970 ?? -1,
            1_786_410_000.5,
            accuracy: 0.001
        )
        XCTAssertTrue(snap.track.isPlaying)
    }

    func testPaused() {
        let raw = [
            "OK",
            "paused",
            "1",
            "Song",
            "Artist",
            "",
            "100",
            "5"
        ].joined(separator: sep)
        let snap = MusicNowPlayingParser.parse(raw)
        XCTAssertEqual(snap.availability, .ready)
        XCTAssertFalse(snap.track.isPlaying)
    }
}

final class NowPlayingSelectorTests: XCTestCase {
    func testPrefersPlayingMusicOverPausedSpotify() {
        let spotify = NowPlayingSnapshot(
            availability: .ready,
            track: Track(
                id: "s", name: "S", artist: "A", album: nil,
                duration: 100, position: 1, isPlaying: false
            ),
            source: .spotify
        )
        let music = NowPlayingSnapshot(
            availability: .ready,
            track: Track(
                id: "m", name: "M", artist: "B", album: nil,
                duration: 100, position: 1, isPlaying: true
            ),
            source: .appleMusic
        )
        let pick = NowPlayingSelector.pick(spotify: spotify, music: music)
        XCTAssertEqual(pick.source, .appleMusic)
        XCTAssertEqual(pick.track.name, "M")
    }

    func testBothNotRunning() {
        let pick = NowPlayingSelector.pick(
            spotify: .playerNotRunning,
            music: .playerNotRunning
        )
        XCTAssertEqual(pick.availability, .playerNotRunning)
    }

    func testMusicOnly() {
        let music = MusicNowPlayingParser.parse(
            ["OK", "playing", "1", "Song", "Artist", "Al", "90", "3"]
                .joined(separator: MusicAppleScript.fieldSeparator)
        )
        let pick = NowPlayingSelector.pick(
            spotify: NowPlayingSnapshot(
                availability: .playerNotRunning,
                source: .spotify
            ),
            music: music
        )
        XCTAssertEqual(pick.source, .appleMusic)
        XCTAssertTrue(pick.track.isPlaying)
    }

    func testPreferredSourceWinsWhenBothPlayersArePlaying() {
        let spotify = NowPlayingSnapshot(
            availability: .ready,
            track: Track(
                id: "s", name: "S", artist: "A", album: nil,
                duration: 100, position: 1, isPlaying: true
            ),
            source: .spotify
        )
        let music = NowPlayingSnapshot(
            availability: .ready,
            track: Track(
                id: "m", name: "M", artist: "B", album: nil,
                duration: 100, position: 1, isPlaying: true
            ),
            source: .appleMusic
        )

        let pick = NowPlayingSelector.pick(
            spotify: spotify,
            music: music,
            preferredSource: .appleMusic
        )

        XCTAssertEqual(pick.source, .appleMusic)
    }
}
