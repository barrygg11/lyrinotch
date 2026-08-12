import XCTest
@testable import LyrinotchCore

final class PlaybackClockTests: XCTestCase {
    func testInterpolatesWhilePlaying() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clock = PlaybackClock(
            sampledPosition: 30,
            sampledAt: t0,
            isPlaying: true,
            duration: 200
        )
        let later = t0.addingTimeInterval(2.5)
        XCTAssertEqual(clock.position(at: later), 32.5, accuracy: 0.001)
    }

    func testDoesNotAdvanceWhenPaused() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clock = PlaybackClock(
            sampledPosition: 12,
            sampledAt: t0,
            isPlaying: false,
            duration: 100
        )
        let later = t0.addingTimeInterval(5)
        XCTAssertEqual(clock.position(at: later), 12, accuracy: 0.001)
    }

    func testCapsAtDuration() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clock = PlaybackClock(
            sampledPosition: 98,
            sampledAt: t0,
            isPlaying: true,
            duration: 100
        )
        XCTAssertEqual(clock.position(at: t0.addingTimeInterval(10)), 100, accuracy: 0.001)
    }

    func testPauseFoldsElapsedIntoSample() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = PlaybackClock(
            sampledPosition: 10,
            sampledAt: t0,
            isPlaying: true,
            duration: 100
        )
        let t1 = t0.addingTimeInterval(3)
        clock.setPlaying(false, at: t1)
        XCTAssertFalse(clock.isPlaying)
        XCTAssertEqual(clock.position(at: t1.addingTimeInterval(5)), 13, accuracy: 0.001)
    }

    func testSeekResetsSample() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = PlaybackClock(
            sampledPosition: 10,
            sampledAt: t0,
            isPlaying: true,
            duration: 100
        )
        let t1 = t0.addingTimeInterval(1)
        clock.seek(to: 40, at: t1)
        XCTAssertEqual(clock.position(at: t1.addingTimeInterval(2)), 42, accuracy: 0.001)
    }

    func testGraduallyReconcilesSmallPlayerJumps() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var clock = PlaybackClock(
            sampledPosition: 20,
            sampledAt: t0,
            isPlaying: true,
            duration: 200
        )
        let t1 = t0.addingTimeInterval(1.0)
        // Player reports 20.2 while local estimate is 21.0. Move toward it
        // without snapping all the way back to the previous lyric line.
        clock.sample(position: 20.2, isPlaying: true, duration: 200, at: t1)
        XCTAssertEqual(clock.position(at: t1), 20.72, accuracy: 0.01)

        // Repeated reports converge instead of being ignored forever.
        clock.sample(position: 20.2, isPlaying: true, duration: 200, at: t1)
        XCTAssertLessThan(clock.position(at: t1), 20.72)
        XCTAssertGreaterThan(clock.position(at: t1), 20.2)

        // Real seek backward should still apply.
        let t2 = t1.addingTimeInterval(0.2)
        clock.sample(position: 5, isPlaying: true, duration: 200, at: t2)
        XCTAssertEqual(clock.position(at: t2), 5, accuracy: 0.05)
    }

    func testTrackSampleUsesPlayerSamplingTimeInsteadOfReceiptTime() {
        let sampledAt = Date(timeIntervalSince1970: 1_000)
        let receivedAt = sampledAt.addingTimeInterval(3)
        var clock = PlaybackClock()
        let track = makeTrack(id: "same", position: 30, sampledAt: sampledAt)

        XCTAssertTrue(clock.sample(from: track, at: receivedAt))
        XCTAssertEqual(clock.sampledAt, sampledAt)
        XCTAssertEqual(clock.position(at: receivedAt), 33, accuracy: 0.001)
    }

    func testRejectsOlderSampleForSameTrack() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = oldDate.addingTimeInterval(2)
        var clock = PlaybackClock()

        XCTAssertTrue(clock.sample(from: makeTrack(id: "same", position: 32, sampledAt: newDate)))
        let acceptedState = clock
        XCTAssertFalse(clock.sample(from: makeTrack(id: "same", position: 10, sampledAt: oldDate)))
        XCTAssertEqual(clock, acceptedState)
    }

    func testAcceptsOlderTimestampWhenTrackChanges() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = oldDate.addingTimeInterval(2)
        var clock = PlaybackClock()

        XCTAssertTrue(clock.sample(from: makeTrack(id: "first", position: 32, sampledAt: newDate)))
        XCTAssertTrue(clock.sample(from: makeTrack(id: "second", position: 4, sampledAt: oldDate)))
        XCTAssertEqual(clock.sampledAt, oldDate)
        XCTAssertEqual(clock.position(at: oldDate), 4, accuracy: 0.001)
    }

    func testSameCatalogIDFromDifferentPlayersIsANewTrack() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = oldDate.addingTimeInterval(2)
        var clock = PlaybackClock()

        XCTAssertTrue(
            clock.sample(
                from: makeTrack(
                    id: "shared",
                    position: 32,
                    sampledAt: newDate,
                    source: .spotify
                )
            )
        )
        XCTAssertTrue(
            clock.sample(
                from: makeTrack(
                    id: "shared",
                    position: 4,
                    sampledAt: oldDate,
                    source: .appleMusic
                )
            )
        )
        XCTAssertEqual(clock.sampledAt, oldDate)
        XCTAssertEqual(clock.position(at: oldDate), 4, accuracy: 0.001)
    }

    private func makeTrack(
        id: String,
        position: TimeInterval,
        sampledAt: Date,
        source: MusicPlayerSource? = nil
    ) -> Track {
        Track(
            id: id,
            name: "Song \(id)",
            artist: "Artist",
            album: nil,
            duration: 200,
            position: position,
            isPlaying: true,
            positionSampledAt: sampledAt,
            source: source
        )
    }
}
