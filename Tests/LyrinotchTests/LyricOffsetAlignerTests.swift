import XCTest
@testable import LyrinotchCore

final class LyricOffsetAlignerTests: XCTestCase {
    func testRecoversKnownPositiveOffset() {
        let hop = 0.05
        let start: TimeInterval = 0
        let duration = 40.0
        let bins = Int(duration / hop)
        var energy = [Float](repeating: 0.05, count: bins)

        let trueOffset = 1.2
        let lyricTimes: [TimeInterval] = [5, 9, 13, 17, 21, 25]
        for L in lyricTimes {
            let p = L - trueOffset
            let idx = Int(((p - start) / hop).rounded())
            guard energy.indices.contains(idx) else { continue }
            for d in -1...2 where energy.indices.contains(idx + d) {
                energy[idx + d] = d == 0 ? 1.0 : 0.45
            }
        }

        let onset = LyricOffsetAligner.onsetStrength(fromEnergy: energy)
        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: start,
            lyricTimes: lyricTimes,
            searchRadius: 1.5,
            step: 0.05
        )
        guard let result else {
            return XCTFail("A clear repeated onset pattern should produce an offset")
        }
        XCTAssertEqual(result.offset, trueOffset, accuracy: 0.25)
        XCTAssertLessThanOrEqual(abs(result.offset), 1.5 + 0.01)
    }

    func testRecoversKnownNegativeOffset() {
        let hop = 0.05
        let start: TimeInterval = 0
        let bins = Int(35.0 / hop)
        var energy = [Float](repeating: 0.04, count: bins)
        let trueOffset = -1.0
        let lyricTimes: [TimeInterval] = [6, 10, 14, 18, 22]
        for L in lyricTimes {
            let p = L - trueOffset
            let idx = Int(((p - start) / hop).rounded())
            guard energy.indices.contains(idx) else { continue }
            energy[idx] = 1.0
            if energy.indices.contains(idx + 1) { energy[idx + 1] = 0.55 }
        }
        let onset = LyricOffsetAligner.onsetStrength(fromEnergy: energy)
        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: start,
            lyricTimes: lyricTimes,
            searchRadius: 1.5
        )
        guard let result else {
            return XCTFail("A clear repeated onset pattern should produce an offset")
        }
        XCTAssertEqual(result.offset, trueOffset, accuracy: 0.25)
    }

    func testRejectsSilence() {
        let energy = [Float](repeating: 0.000_01, count: 200)
        let onset = LyricOffsetAligner.onsetStrength(fromEnergy: energy)
        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: 0.05,
            envelopeStartPlayback: 0,
            lyricTimes: [1, 2, 3, 4, 5]
        )
        XCTAssertNil(result)
    }

    func testRejectsUnrelatedPeriodicBeats() {
        let hop = 0.05
        var energy = [Float](repeating: 0.04, count: Int(24 / hop))
        for beat in stride(from: 0.5, through: 23.5, by: 0.5) {
            let index = Int((beat / hop).rounded())
            energy[index] = 1
        }
        let onset = LyricOffsetAligner.onsetStrength(fromEnergy: energy)
        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: [4.13, 7.82, 12.24, 16.91, 21.17]
        )
        XCTAssertNil(result, "A regular drum beat must not look like aligned lyric onsets")
    }

    func testRejectsEquivalentBeatAlignedPeaks() {
        let hop = 0.05
        var onset = [Float](repeating: 0, count: Int(30 / hop))
        for beat in stride(from: 0.5, through: 29.5, by: 0.5) {
            onset[Int((beat / hop).rounded())] = 1
        }

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: [5, 9, 13, 17, 21, 25]
        )

        XCTAssertNil(result, "Equivalent beat phases must be treated as ambiguous")
    }

    func testRejectsDominantDownbeatsThatHideTheVocalOffset() {
        let hop = 0.05
        var onset = [Float](repeating: 0, count: Int(30 / hop))
        for beat in stride(from: 0.5, through: 29.5, by: 0.5) {
            let index = Int((beat / hop).rounded())
            onset[index] = beat.truncatingRemainder(dividingBy: 2) == 0 ? 1 : 0.35
        }

        let lyricTimes: [TimeInterval] = [5, 9, 13, 17, 21, 25]
        let vocalOffset = 0.4
        for lyricTime in lyricTimes {
            let index = Int(((lyricTime - vocalOffset) / hop).rounded())
            onset[index] = max(onset[index], 0.7)
        }

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: lyricTimes
        )

        XCTAssertNil(result, "Repeated downbeats must not override weaker vocal evidence")
    }

    func testRejectsPeakAtSearchBoundary() {
        let hop = 0.05
        let lyricTimes: [TimeInterval] = [5.2, 9.1, 13.7, 18.4, 23.8]
        let onset = syntheticOnsets(
            hop: hop,
            duration: 30,
            lyricTimes: lyricTimes,
            offset: 1.5
        )

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: lyricTimes,
            searchRadius: 1.5
        )

        XCTAssertNil(result, "A truncated boundary peak needs a wider or re-centered search")
    }

    func testRecoversClearOffsetsBeyondLegacyWindow() {
        let hop = 0.05
        let lyricTimes: [TimeInterval] = [5.2, 9.1, 13.7, 18.4, 23.8, 28.6]

        for trueOffset in [-2.0, 2.0] {
            let onset = syntheticOnsets(
                hop: hop,
                duration: 34,
                lyricTimes: lyricTimes,
                offset: trueOffset
            )
            let result = LyricOffsetAligner.bestOffset(
                onsetEnvelope: onset,
                hopSeconds: hop,
                envelopeStartPlayback: 0,
                lyricTimes: lyricTimes
            )

            XCTAssertEqual(result?.offset ?? .nan, trueOffset, accuracy: 0.1)
        }
    }

    func testSearchCanBeCenteredOnCurrentlyAppliedTotalOffset() {
        let hop = 0.05
        let lyricTimes: [TimeInterval] = [7.2, 11.1, 15.7, 20.4, 25.8]
        let onset = syntheticOnsets(
            hop: hop,
            duration: 30,
            lyricTimes: lyricTimes,
            offset: 4.0
        )

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: lyricTimes,
            currentTotalOffset: 3.5,
            searchRadius: 1
        )

        XCTAssertEqual(result?.offset ?? .nan, 4.0, accuracy: 0.1)
    }

    @available(*, deprecated, message: "Exercises the deprecated source-compatible entry point")
    func testLegacyAbsoluteSearchRangeRemainsSourceCompatible() {
        let hop = 0.05
        let lyricTimes: [TimeInterval] = [5.2, 9.1, 13.7, 18.4, 23.8]
        let onset = syntheticOnsets(
            hop: hop,
            duration: 30,
            lyricTimes: lyricTimes,
            offset: 0.8
        )

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: lyricTimes,
            searchRange: -1.5...1.5
        )

        XCTAssertEqual(result?.offset ?? .nan, 0.8, accuracy: 0.1)
    }

    func testLyricCountInWindow() {
        let times: [TimeInterval] = [5, 10, 12, 30]
        XCTAssertEqual(
            LyricOffsetAligner.lyricCount(inPlaybackWindow: 9, duration: 10, lyricTimes: times),
            2
        )
        XCTAssertEqual(
            LyricOffsetAligner.lyricCount(inPlaybackWindow: 0, duration: 6, lyricTimes: times),
            1
        )
    }

    func testStackedBilingualLinesCountAsOneSingingPoint() {
        let times: [TimeInterval] = [
            12.08, 8, .nan, 12, 8.12, -1, 12.17, 20
        ]

        XCTAssertEqual(
            LyricOffsetAligner.distinctSingingPointTimes(from: times),
            [8, 12, 20]
        )
        XCTAssertEqual(
            LyricOffsetAligner.lyricCount(
                inPlaybackWindow: 7.9,
                duration: 4.5,
                lyricTimes: times
            ),
            2
        )
    }

    func testPlaybackWindowKeepsAStackWhoseUsableTimestampIsInsideBoundary() {
        XCTAssertEqual(
            LyricOffsetAligner.lyricCount(
                inPlaybackWindow: 10,
                duration: 5,
                lyricTimes: [9.74, 9.8, 15.2, 15.26]
            ),
            2
        )
    }

    func testStackedLinesDoNotInflateAlignmentHits() {
        let hop = 0.05
        let singingPoints: [TimeInterval] = [5, 9, 13, 17, 21]
        let stackedTimes = singingPoints.flatMap { [$0, $0 + 0.06, $0 + 0.12] }
        let onset = syntheticOnsets(
            hop: hop,
            duration: 26,
            lyricTimes: singingPoints,
            offset: 0.8
        )

        let result = LyricOffsetAligner.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hop,
            envelopeStartPlayback: 0,
            lyricTimes: stackedTimes,
            searchRadius: 1.5
        )

        XCTAssertEqual(result?.offset ?? .nan, 0.8, accuracy: 0.1)
        XCTAssertEqual(result?.hits, singingPoints.count)
    }

    func testStoreRoundTrip() {
        let store = TrackLyricOffsetStore.ephemeral()
        let track = Track(
            id: "spotify:abc",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 200,
            position: 10,
            isPlaying: true
        )
        let key = TrackLyricOffsetStore.trackKey(for: track)
        store.set(
            TrackLyricOffsetEntry(offsetSeconds: 1.25, confidence: 0.7, source: "auto"),
            forTrackKey: key
        )
        let loaded = store.offset(forTrackKey: key)
        XCTAssertEqual(loaded?.offsetSeconds ?? 0, 1.25, accuracy: 0.001)
        XCTAssertEqual(loaded?.source, "auto")
        store.remove(forTrackKey: key)
        XCTAssertNil(store.offset(forTrackKey: key))
    }

    private func syntheticOnsets(
        hop: TimeInterval,
        duration: TimeInterval,
        lyricTimes: [TimeInterval],
        offset: TimeInterval
    ) -> [Float] {
        var onset = [Float](repeating: 0, count: Int(duration / hop))
        for lyricTime in lyricTimes {
            let index = Int(((lyricTime - offset) / hop).rounded())
            guard onset.indices.contains(index) else { continue }
            onset[index] = 1
        }
        return onset
    }
}
