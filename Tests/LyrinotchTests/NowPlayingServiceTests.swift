import XCTest
@testable import LyrinotchCore

private struct StubExecutor: SpotifyScriptExecuting {
    var result: Result<String, Error>

    func run(script: String) async throws -> String {
        _ = script
        return try result.get()
    }
}

final class NowPlayingServiceTests: XCTestCase {
    func testSnapshotReadyFromExecutor() async {
        let sep = SpotifyAppleScript.fieldSeparator
        let raw = [
            "OK",
            "playing",
            "spotify:track:1",
            "Song",
            "Artist",
            "Album",
            "90000",
            "10",
            "1786410000.25"
        ].joined(separator: sep)

        let service = NowPlayingService(executor: StubExecutor(result: .success(raw)))
        let snap = await service.snapshot()

        XCTAssertEqual(snap.availability, .ready)
        XCTAssertEqual(snap.track.name, "Song")
        XCTAssertTrue(snap.track.isPlaying)
        XCTAssertEqual(
            snap.track.positionSampledAt?.timeIntervalSince1970 ?? -1,
            1_786_410_000.25,
            accuracy: 0.001
        )

        let track = await service.currentTrack()
        XCTAssertEqual(track.name, "Song")
    }

    func testSnapshotMapsExecutorFailure() async {
        let service = NowPlayingService(
            executor: StubExecutor(result: .failure(SpotifyScriptError.emptyOutput))
        )
        let snap = await service.snapshot()
        XCTAssertEqual(snap.availability, .error)
        XCTAssertNotNil(snap.detail)

        let track = await service.currentTrack()
        XCTAssertEqual(track, .empty)
    }

    func testSnapshotNotRunning() async {
        let service = NowPlayingService(
            executor: StubExecutor(result: .success("NOT_RUNNING"))
        )
        let snap = await service.snapshot()
        XCTAssertEqual(snap.availability, .playerNotRunning)
    }

    func testActivePlayerAffinitySkipsOtherPlayerWhileStillPlaying() async {
        let executor = RoutingExecutor(
            spotify: [Self.spotifyPayload(state: "playing", name: "Spotify Song")],
            music: [Self.musicPayload(state: "paused", name: "Music Song")]
        )
        let service = NowPlayingService(executor: executor)

        let first = await service.snapshot()
        let second = await service.snapshot()
        let counts = await executor.counts()

        XCTAssertEqual(first.source, .spotify)
        XCTAssertEqual(second.source, .spotify)
        XCTAssertEqual(counts.spotify, 2)
        XCTAssertEqual(counts.music, 1)
    }

    func testPausedActivePlayerChecksAndSwitchesToOtherPlayingPlayer() async {
        let executor = RoutingExecutor(
            spotify: [
                Self.spotifyPayload(state: "playing", name: "Spotify Song"),
                Self.spotifyPayload(state: "paused", name: "Spotify Song")
            ],
            music: [
                Self.musicPayload(state: "paused", name: "Music Song"),
                Self.musicPayload(state: "playing", name: "Music Song")
            ]
        )
        let service = NowPlayingService(executor: executor)

        let first = await service.snapshot()
        let second = await service.snapshot()
        let third = await service.snapshot()
        XCTAssertEqual(first.source, .spotify)
        XCTAssertEqual(second.source, .appleMusic)
        XCTAssertEqual(third.source, .appleMusic)
        let counts = await executor.counts()

        XCTAssertEqual(counts.spotify, 2)
        XCTAssertEqual(counts.music, 3)
    }

    func testFastSecondaryDoesNotStealExplicitPreferredPlayerWithinGrace() async {
        let executor = DelayedRoutingExecutor(
            spotifyDelayMilliseconds: 80,
            spotify: Self.spotifyPayload(state: "playing", name: "Preferred"),
            musicDelayMilliseconds: 0,
            music: Self.musicPayload(state: "playing", name: "Fast Secondary")
        )
        let service = NowPlayingService(
            executor: executor,
            fallbackHedgeDelayMilliseconds: 0,
            fallbackPrimaryGraceMilliseconds: 200
        )

        let snapshot = await service.snapshot(preferredSource: .spotify)

        XCTAssertEqual(snapshot.source, .spotify)
        XCTAssertEqual(snapshot.track.name, "Preferred")
    }

    func testSecondaryCanWinAfterDeadlineWhenPrimaryIsHung() async {
        let executor = DelayedRoutingExecutor(
            spotifyDelayMilliseconds: 1_000,
            spotify: Self.spotifyPayload(state: "playing", name: "Hung Preferred"),
            musicDelayMilliseconds: 80,
            music: Self.musicPayload(state: "playing", name: "Fallback")
        )
        let service = NowPlayingService(
            executor: executor,
            fallbackHedgeDelayMilliseconds: 0,
            fallbackPrimaryGraceMilliseconds: 20
        )

        let snapshot = await service.snapshot(preferredSource: .spotify)

        XCTAssertEqual(snapshot.source, .appleMusic)
        XCTAssertEqual(snapshot.track.name, "Fallback")
    }

    func testInitialPlayingPlayerDoesNotWaitForHungInactivePlayer() async {
        let executor = DelayedRoutingExecutor(
            spotifyDelayMilliseconds: 10,
            spotify: Self.spotifyPayload(state: "playing", name: "Active"),
            musicDelayMilliseconds: 1_000,
            music: Self.musicPayload(state: "paused", name: "Hung Inactive")
        )
        let service = NowPlayingService(executor: executor)

        let snapshot = await service.snapshot()
        let completions = await executor.completionCounts()

        XCTAssertEqual(snapshot.source, .spotify)
        XCTAssertEqual(snapshot.track.name, "Active")
        XCTAssertEqual(completions.spotify, 1)
        XCTAssertEqual(completions.music, 0)
    }

    private static func spotifyPayload(state: String, name: String) -> String {
        ["OK", state, "spotify-id", name, "Artist", "Album", "180000", "10"]
            .joined(separator: SpotifyAppleScript.fieldSeparator)
    }

    private static func musicPayload(state: String, name: String) -> String {
        ["OK", state, "music-id", name, "Artist", "Album", "180", "10"]
            .joined(separator: MusicAppleScript.fieldSeparator)
    }
}

private actor DelayedRoutingExecutor: AppleScriptExecuting {
    let spotifyDelayMilliseconds: Int
    let spotify: String
    let musicDelayMilliseconds: Int
    let music: String
    private var spotifyCompletions = 0
    private var musicCompletions = 0

    init(
        spotifyDelayMilliseconds: Int,
        spotify: String,
        musicDelayMilliseconds: Int,
        music: String
    ) {
        self.spotifyDelayMilliseconds = spotifyDelayMilliseconds
        self.spotify = spotify
        self.musicDelayMilliseconds = musicDelayMilliseconds
        self.music = music
    }

    func run(script: String) async throws -> String {
        if script == SpotifyAppleScript.nowPlayingScript {
            try await Task.sleep(
                nanoseconds: UInt64(max(0, spotifyDelayMilliseconds)) * 1_000_000
            )
            spotifyCompletions += 1
            return spotify
        }
        if script == MusicAppleScript.nowPlayingScript {
            try await Task.sleep(
                nanoseconds: UInt64(max(0, musicDelayMilliseconds)) * 1_000_000
            )
            musicCompletions += 1
            return music
        }
        throw AppleScriptError.emptyOutput
    }

    func completionCounts() -> (spotify: Int, music: Int) {
        (spotifyCompletions, musicCompletions)
    }
}

private actor RoutingExecutor: AppleScriptExecuting {
    private var spotifyResponses: [String]
    private var musicResponses: [String]
    private var spotifyCount = 0
    private var musicCount = 0

    init(spotify: [String], music: [String]) {
        spotifyResponses = spotify
        musicResponses = music
    }

    func run(script: String) async throws -> String {
        if script == SpotifyAppleScript.nowPlayingScript {
            spotifyCount += 1
            return spotifyResponses[min(spotifyCount - 1, spotifyResponses.count - 1)]
        }
        if script == MusicAppleScript.nowPlayingScript {
            musicCount += 1
            return musicResponses[min(musicCount - 1, musicResponses.count - 1)]
        }
        throw AppleScriptError.emptyOutput
    }

    func counts() -> (spotify: Int, music: Int) {
        (spotifyCount, musicCount)
    }
}
