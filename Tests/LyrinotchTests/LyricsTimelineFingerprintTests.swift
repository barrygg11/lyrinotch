import XCTest
@testable import LyrinotchCore

final class LyricsTimelineFingerprintTests: XCTestCase {
    func testFingerprintIsStableForEquivalentTimeline() {
        let first = synced(source: "lrclib", providerID: "42", shift: 0)
        let second = synced(source: "lrclib", providerID: "42", shift: 0)

        XCTAssertEqual(
            first.timelineFingerprint(duration: 120),
            second.timelineFingerprint(duration: 120)
        )
    }

    func testFingerprintChangesWithTimestampProviderOrBody() {
        let baseline = synced(source: "lrclib", providerID: "42", shift: 0)
            .timelineFingerprint(duration: 120)

        XCTAssertNotEqual(
            baseline,
            synced(source: "lrclib", providerID: "42", shift: 0.25)
                .timelineFingerprint(duration: 120)
        )
        XCTAssertNotEqual(
            baseline,
            synced(source: "netease", providerID: "42", shift: 0)
                .timelineFingerprint(duration: 120)
        )
        XCTAssertNotEqual(
            baseline,
            synced(source: "lrclib", providerID: "different", shift: 0)
                .timelineFingerprint(duration: 120)
        )
    }

    func testPlainFingerprintIncludesEstimatedTimelineDuration() {
        let snapshot = LyricsSnapshot(
            availability: .plain,
            plainLines: ["one", "two"],
            source: "apple-music"
        )

        XCTAssertNotEqual(
            snapshot.timelineFingerprint(duration: 100),
            snapshot.timelineFingerprint(duration: 120)
        )
    }

    func testLegacyOffsetEntryDecodesWithoutFingerprint() throws {
        let json = #"{"offsetSeconds":0.5,"confidence":0.9,"updatedAt":0,"source":"auto"}"#
        let decoded = try JSONDecoder().decode(
            TrackLyricOffsetEntry.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(decoded.lyricsFingerprint)
        XCTAssertNil(decoded.audioRoute)
    }

    func testFingerprintRejectsNonFiniteTimelineValues() {
        let synced = LyricsSnapshot(
            availability: .synced,
            lines: [LyricLine(time: .nan, text: "invalid")]
        )
        let plain = LyricsSnapshot(
            availability: .plain,
            plainLines: ["line"]
        )

        XCTAssertNil(synced.timelineFingerprint(duration: 120))
        XCTAssertNil(plain.timelineFingerprint(duration: .infinity))
    }

    private func synced(
        source: String,
        providerID: String,
        shift: TimeInterval
    ) -> LyricsSnapshot {
        LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 1 + shift, text: "one"),
                LyricLine(time: 5 + shift, text: "two")
            ],
            source: source,
            matchedTrack: LyricsMatchMetadata(
                title: "Song",
                artist: "Artist",
                duration: 120,
                providerID: providerID
            )
        )
    }
}
