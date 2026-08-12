import XCTest
@testable import LyrinotchCore

final class LyricLineTests: XCTestCase {
    func testActiveIndexBeforeFirstLine() {
        let lines = sampleLines()
        XCTAssertNil(LyricLine.activeIndex(in: lines, at: 0.5))
    }

    func testActiveIndexOnAndBetweenLines() {
        let lines = sampleLines()
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 1.0), 0)
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 2.5), 0)
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 3.0), 1)
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 10.0), 2)
    }

    func testActiveIndexEmpty() {
        XCTAssertNil(LyricLine.activeIndex(in: [], at: 1.0))
    }

    func testTimeString() {
        XCTAssertEqual(LyricLine(time: 0, text: "a").timeString, "0:00")
        XCTAssertEqual(LyricLine(time: 65, text: "b").timeString, "1:05")
    }

    func testNextNonEmptyLineSkipsBlankBeats() {
        let lines = [
            LyricLine(time: 4, text: "before"),
            LyricLine(time: 8, text: "   "),
            LyricLine(time: 12.2, text: "next")
        ]
        XCTAssertEqual(
            LyricLine.nextNonEmpty(in: lines, after: 5),
            LyricLine(time: 12.2, text: "next")
        )
        XCTAssertNil(LyricLine.nextNonEmpty(in: lines, after: 12.2))
    }

    func testSecondsUntilRoundsUpAndNeverGoesNegative() {
        let line = LyricLine(time: 12.2, text: "next")
        XCTAssertEqual(line.secondsUntil(startingAt: 5), 8)
        XCTAssertEqual(line.secondsUntil(startingAt: 12.2), 0)
        XCTAssertEqual(line.secondsUntil(startingAt: 20), 0)
    }

    func testUnrepresentableTimeUsesSafeFallbacks() {
        let line = LyricLine(time: 1e20, text: "future")

        XCTAssertEqual(line.timeString, "--:--")
        XCTAssertEqual(line.secondsUntil(startingAt: 0), 0)
        XCTAssertEqual(line.secondsUntil(startingAt: -1e20), 0)
    }

    func testTrackDisplayTitle() {
        XCTAssertEqual(Track.empty.displayTitle, L10n.t("track.not_playing"))
        XCTAssertEqual(
            Track(id: nil, name: "Song", artist: "Artist", album: nil, duration: nil, position: nil, isPlaying: true).displayTitle,
            "Artist — Song"
        )
    }

    private func sampleLines() -> [LyricLine] {
        [
            LyricLine(time: 1.0, text: "first"),
            LyricLine(time: 3.0, text: "second"),
            LyricLine(time: 8.0, text: "third")
        ]
    }
}
