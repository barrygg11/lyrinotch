import XCTest
@testable import LyrinotchCore

final class LyricCalibrationPolicyTests: XCTestCase {
    func testStrongSampleAppliesImmediately() {
        let sample = LyricCalibrationSample(totalOffset: 0.8, confidence: 0.84)
        XCTAssertEqual(LyricCalibrationPolicy.evaluate(previous: nil, new: sample), .apply(sample))
    }

    func testMediumSampleRequiresConsistentConfirmation() {
        let first = LyricCalibrationSample(totalOffset: 0.70, confidence: 0.70)
        let second = LyricCalibrationSample(totalOffset: 0.82, confidence: 0.68)

        XCTAssertEqual(
            LyricCalibrationPolicy.evaluate(previous: nil, new: first),
            .waitForConfirmation(first)
        )

        guard case .apply(let combined) = LyricCalibrationPolicy.evaluate(
            previous: first,
            new: second
        ) else {
            return XCTFail("Agreeing calibration windows should be applied")
        }
        XCTAssertEqual(combined.totalOffset, 0.76, accuracy: 0.02)
        XCTAssertEqual(combined.confidence, 0.70, accuracy: 0.000_1)
    }

    func testWeakSampleNeverChangesTimeline() {
        let sample = LyricCalibrationSample(totalOffset: 1.5, confidence: 0.64)
        XCTAssertEqual(LyricCalibrationPolicy.evaluate(previous: nil, new: sample), .reject)
    }

    func testInconsistentSamplesKeepStrongerCandidate() {
        let first = LyricCalibrationSample(totalOffset: -0.9, confidence: 0.70)
        let second = LyricCalibrationSample(totalOffset: 0.8, confidence: 0.66)
        XCTAssertEqual(
            LyricCalibrationPolicy.evaluate(previous: first, new: second),
            .waitForConfirmation(first)
        )
    }

    func testAgreementDoesNotInflateCorrelatedMicrophoneConfidence() {
        let first = LyricCalibrationSample(totalOffset: -0.1, confidence: 0.67)
        let second = LyricCalibrationSample(totalOffset: -0.1, confidence: 0.67)

        guard case .apply(let combined) = LyricCalibrationPolicy.evaluate(
            previous: first,
            new: second
        ) else {
            return XCTFail("Trusted agreeing samples should still confirm their offset")
        }

        XCTAssertEqual(combined.confidence, 0.67, accuracy: 0.000_1)
    }

    func testTrackResidualDoesNotDoubleCountGlobalOffset() {
        XCTAssertEqual(
            LyricCalibrationPolicy.trackResidual(
                measuredTotalOffset: 0.8,
                globalOffset: 0.5
            ),
            0.3,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            LyricCalibrationPolicy.trackResidual(
                measuredTotalOffset: -0.6,
                globalOffset: -0.2
            ),
            -0.4,
            accuracy: 0.000_1
        )
    }

    func testAutomaticAttemptsAreBounded() {
        XCTAssertTrue(LyricCalibrationPolicy.allowsAnotherAttempt(afterStartedAttempts: 0))
        XCTAssertTrue(LyricCalibrationPolicy.allowsAnotherAttempt(afterStartedAttempts: 2))
        XCTAssertFalse(LyricCalibrationPolicy.allowsAnotherAttempt(afterStartedAttempts: 3))
        XCTAssertFalse(LyricCalibrationPolicy.allowsAnotherAttempt(afterStartedAttempts: 99))
    }

    func testRejectsWeakAutomaticOffsetsSavedByOlderVersions() {
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(source: "auto", confidence: 0.64)
        )
        XCTAssertTrue(
            LyricCalibrationPolicy.acceptsStoredOffset(source: "auto", confidence: 0.65)
        )
        XCTAssertTrue(
            LyricCalibrationPolicy.acceptsStoredOffset(source: "manual", confidence: 0)
        )
        XCTAssertTrue(
            LyricCalibrationPolicy.acceptsStoredOffset(source: "tap", confidence: 0)
        )
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(source: "unknown", confidence: 1)
        )
    }

    func testStoredAutomaticOffsetRequiresMatchingTimelineRouteAndFreshness() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let entry = TrackLyricOffsetEntry(
            offsetSeconds: 0.7,
            confidence: 0.8,
            updatedAt: now.addingTimeInterval(-60),
            source: "auto",
            lyricsFingerprint: "timeline-a",
            audioRoute: "speakers"
        )

        XCTAssertTrue(
            LyricCalibrationPolicy.acceptsStoredOffset(
                entry,
                lyricsFingerprint: "timeline-a",
                audioRoute: "speakers",
                now: now
            )
        )
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(
                entry,
                lyricsFingerprint: "timeline-b",
                audioRoute: "speakers",
                now: now
            )
        )
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(
                entry,
                lyricsFingerprint: "timeline-a",
                audioRoute: "bluetooth",
                now: now
            )
        )

        var expired = entry
        expired.updatedAt = now.addingTimeInterval(
            -LyricCalibrationPolicy.maximumStoredAutomaticAge - 1
        )
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(
                expired,
                lyricsFingerprint: "timeline-a",
                audioRoute: "speakers",
                now: now
            )
        )
    }

    func testManualStoredOffsetRequiresTimelineButNotAudioRouteOrAge() {
        let entry = TrackLyricOffsetEntry(
            offsetSeconds: -0.4,
            confidence: 1,
            updatedAt: .distantPast,
            source: "manual",
            lyricsFingerprint: "timeline-a"
        )

        XCTAssertTrue(
            LyricCalibrationPolicy.acceptsStoredOffset(
                entry,
                lyricsFingerprint: "timeline-a",
                audioRoute: "headphones"
            )
        )
        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(
                entry,
                lyricsFingerprint: "timeline-b",
                audioRoute: "headphones"
            )
        )
    }

    func testLegacyStoredOffsetWithoutTimelineIsRejected() {
        let legacy = TrackLyricOffsetEntry(
            offsetSeconds: 0.6,
            confidence: 0.9,
            source: "auto"
        )

        XCTAssertFalse(
            LyricCalibrationPolicy.acceptsStoredOffset(
                legacy,
                lyricsFingerprint: "timeline-a",
                audioRoute: "speakers"
            )
        )
    }
}
