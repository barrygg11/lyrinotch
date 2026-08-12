import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class LyricOffsetCalibratorTests: XCTestCase {
    func testWaitingWindowUsesCurrentlyAdjustedTimelinePosition() {
        let adjustedPosition = LyricCalibrationTimeline.adjustedPosition(
            playbackPosition: 10,
            currentTotalOffset: 4
        )

        XCTAssertEqual(adjustedPosition, 14, accuracy: 0.001)
        XCTAssertEqual(
            LyricOffsetAligner.lyricCount(
                inPlaybackWindow: adjustedPosition,
                duration: 8,
                lyricTimes: [9, 15, 18, 21, 30]
            ),
            3
        )
    }

    func testFocusedTimesCoverEntireSearchAroundCurrentOffset() {
        let focused = LyricCalibrationTimeline.focusedLyricTimes(
            [100.99, 101, 110, 121, 121.01],
            envelopeStartPlayback: 100,
            envelopeDuration: 14,
            currentTotalOffset: 4,
            searchRadius: 2.5,
            padding: 0.5
        )

        XCTAssertEqual(focused, [101, 110, 121])
    }

    func testFocusedTimesCollapseStackedTranslations() {
        let focused = LyricCalibrationTimeline.focusedLyricTimes(
            [101, 101.08, 101.16, 110, 110.1, 121],
            envelopeStartPlayback: 100,
            envelopeDuration: 14,
            currentTotalOffset: 4,
            searchRadius: 2.5,
            padding: 0.5
        )

        XCTAssertEqual(focused, [101, 110, 121])
    }

    func testAnalysisSearchIsCenteredOnCurrentTotalOffset() {
        let hop = 0.05
        let lyricTimes: [TimeInterval] = [8.2, 12.1, 17.7, 22.4, 27.8]
        let trueOffset: TimeInterval = 4
        var onset = [Float](repeating: 0, count: Int(30 / hop))
        for lyricTime in lyricTimes {
            let index = Int(((lyricTime - trueOffset) / hop).rounded())
            onset[index] = 1
        }

        let result = LyricCalibrationTimeline.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: lyricTimes,
            currentTotalOffset: 3.5,
            searchRadius: 1
        )

        XCTAssertEqual(result?.offset ?? .nan, trueOffset, accuracy: 0.1)
    }

    func testPlaybackContinuityAcceptsNormalElapsedTime() {
        var continuity = LyricCalibrationPlaybackContinuity(
            position: 20,
            uptime: 100
        )

        XCTAssertTrue(continuity.observe(position: 20.1, uptime: 100.1))
        XCTAssertTrue(continuity.observe(position: 20.52, uptime: 100.5))
        XCTAssertTrue(continuity.observe(position: 21.03, uptime: 101.0))
    }

    func testPlaybackContinuityRejectsSingleSeek() {
        var continuity = LyricCalibrationPlaybackContinuity(
            position: 20,
            uptime: 100
        )

        XCTAssertTrue(continuity.observe(position: 20.1, uptime: 100.1))
        XCTAssertFalse(continuity.observe(position: 24.2, uptime: 100.2))
    }

    func testPlaybackContinuityRejectsSeekSmoothedAcrossSamples() {
        var continuity = LyricCalibrationPlaybackContinuity(
            position: 20,
            uptime: 100
        )

        XCTAssertTrue(continuity.observe(position: 20.3, uptime: 100.5))
        XCTAssertTrue(continuity.observe(position: 20.6, uptime: 101.0))
        XCTAssertFalse(continuity.observe(position: 20.9, uptime: 101.5))
    }

    func testPlaybackContinuityRejectsInvalidClockSample() {
        var continuity = LyricCalibrationPlaybackContinuity(
            position: 20,
            uptime: 100
        )

        XCTAssertFalse(continuity.observe(position: .nan, uptime: 100.1))
    }
}
