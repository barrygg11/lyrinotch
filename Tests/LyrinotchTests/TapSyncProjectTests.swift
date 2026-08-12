import Foundation
import XCTest
@testable import LyrinotchCore

final class TapSyncProjectTests: XCTestCase {
    func testPrepareRejectsUnsupportedEmptyAndGeneratedLyrics() throws {
        let track = makeTrack()

        XCTAssertThrowsError(
            try TapSyncProject(
                track: track,
                lyrics: LyricsSnapshot(availability: .notFound)
            )
        ) { XCTAssertEqual($0 as? TapSyncProjectError, .unsupportedLyrics) }

        XCTAssertThrowsError(
            try TapSyncProject(
                track: track,
                lyrics: LyricsSnapshot(availability: .plain, plainLines: ["  ", "\n"])
            )
        ) { XCTAssertEqual($0 as? TapSyncProjectError, .noUsableLines) }

        XCTAssertThrowsError(
            try TapSyncProject(
                track: track,
                lyrics: LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "line")],
                    source: TapSyncProject.outputSource,
                    timingBaseFingerprint: "v1:base"
                )
            )
        ) { XCTAssertEqual($0 as? TapSyncProjectError, .unsupportedLyrics) }
    }

    func testRecordReplaceUndoAndReset() throws {
        var project = try makeProject(lines: ["one", "two", "three", "four"])

        try project.recordOrReplaceAnchor(lineIndex: 1, playbackTime: 10)
        try project.recordOrReplaceAnchor(lineIndex: 3, playbackTime: 30)
        try project.recordOrReplaceAnchor(lineIndex: 1, playbackTime: 12)
        XCTAssertEqual(
            project.anchors,
            [
                TapSyncAnchor(lineIndex: 1, playbackTime: 12),
                TapSyncAnchor(lineIndex: 3, playbackTime: 30)
            ]
        )

        XCTAssertTrue(project.undoLastEdit())
        XCTAssertEqual(project.anchors[0], TapSyncAnchor(lineIndex: 1, playbackTime: 10))
        XCTAssertTrue(project.undoLastEdit())
        XCTAssertEqual(project.anchors, [TapSyncAnchor(lineIndex: 1, playbackTime: 10)])
        XCTAssertTrue(project.canUndo)

        project.reset()
        XCTAssertTrue(project.anchors.isEmpty)
        XCTAssertFalse(project.canUndo)
        XCTAssertFalse(project.undoLastEdit())
    }

    func testAnchorValidationPreservesExistingProjectOnFailure() throws {
        var project = try makeProject(lines: ["one", " ", "three", "four"])
        try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 5)
        try project.recordOrReplaceAnchor(lineIndex: 3, playbackTime: 30)
        let original = project

        assertRecordError(.invalidLineIndex, project: &project, line: 8, time: 10)
        assertRecordError(.emptyLyricLine, project: &project, line: 1, time: 10)
        assertRecordError(.invalidPlaybackTime, project: &project, line: 2, time: .nan)
        assertRecordError(.invalidPlaybackTime, project: &project, line: 2, time: -1)
        assertRecordError(.invalidPlaybackTime, project: &project, line: 2, time: 121)
        assertRecordError(.nonMonotonicAnchor, project: &project, line: 2, time: 4)
        assertRecordError(.nonMonotonicAnchor, project: &project, line: 2, time: 35)
        XCTAssertEqual(project, original)
    }

    func testSparseAnchorsInterpolateAndExtrapolateMonotonically() throws {
        var project = try makeProject(
            lines: ["zero", "one", "two", "three", "four", "five"],
            duration: 120
        )
        try project.recordOrReplaceAnchor(lineIndex: 1, playbackTime: 10)
        try project.recordOrReplaceAnchor(lineIndex: 4, playbackTime: 70)

        let resolved = try project.resolvedLines()

        XCTAssertEqual(resolved.map(\.time), [0, 10, 30, 50, 70, 90])
        XCTAssertEqual(resolved.map(\.text), project.lineTexts)
        assertMonotonic(resolved)
    }

    func testOneAnchorUsesBaseCadenceAndCompressesNegativePrefix() throws {
        var project = try makeProject(
            lines: ["zero", "one", "two", "three"],
            duration: 40
        )
        try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 5)

        let resolved = try project.resolvedLines()

        XCTAssertEqual(resolved.map(\.time), [0, 2.5, 5, 15])
        assertMonotonic(resolved)
    }

    func testExistingSyncedGapsShapeInterpolationButAnchorsStayExact() throws {
        let lyrics = LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 0, text: "zero"),
                LyricLine(time: 5, text: "one"),
                LyricLine(time: 30, text: "two"),
                LyricLine(time: 35, text: "three")
            ],
            source: "provider"
        )
        var project = try TapSyncProject(track: makeTrack(duration: 80), lyrics: lyrics)
        try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 10)
        try project.recordOrReplaceAnchor(lineIndex: 3, playbackTime: 50)

        let resolved = try project.resolvedLines()

        XCTAssertEqual(resolved[0].time, 10, accuracy: 0.000_001)
        XCTAssertEqual(resolved[1].time, 15.714_285, accuracy: 0.000_001)
        XCTAssertEqual(resolved[2].time, 44.285_714, accuracy: 0.000_001)
        XCTAssertEqual(resolved[3].time, 50, accuracy: 0.000_001)
        assertMonotonic(resolved)
    }

    func testFullAnchorPassPreservesEveryRecordedTimeExactly() throws {
        var project = try makeProject(lines: ["one", "two", "three", "four"])
        let expected: [TimeInterval] = [8.25, 12.7, 44.125, 67.9]
        for (index, time) in expected.enumerated() {
            try project.recordOrReplaceAnchor(lineIndex: index, playbackTime: time)
        }

        XCTAssertEqual(try project.resolvedLines().map(\.time), expected)
    }

    func testGeneratedSnapshotIsDistinctAndCarriesResumeFingerprint() throws {
        let lyrics = plainLyrics(["one", "two", "three"])
        var project = try TapSyncProject(track: makeTrack(duration: 60), lyrics: lyrics)
        try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 4)
        try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 44)

        let generated = try project.syncedSnapshot()

        XCTAssertEqual(generated.availability, .synced)
        XCTAssertEqual(generated.source, TapSyncProject.outputSource)
        XCTAssertEqual(generated.selectionReason, .manuallySelected)
        XCTAssertEqual(generated.timingBaseFingerprint, project.baseLyricsFingerprint)
        XCTAssertNotEqual(
            generated.timelineFingerprint(duration: 60),
            project.baseLyricsFingerprint
        )
        XCTAssertTrue(project.matches(lyrics: generated, duration: 60))
        XCTAssertTrue(project.matches(lyrics: lyrics, duration: 60))
    }

    func testStaleGeneratedTimingCanResumeLatestProjectRevision() throws {
        let lyrics = plainLyrics(["one", "two", "three"])
        var project = try TapSyncProject(track: makeTrack(duration: 60), lyrics: lyrics)
        try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 4)
        try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 44)
        let previouslyPinned = try project.syncedSnapshot()
        try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 48)

        XCTAssertTrue(project.matches(lyrics: previouslyPinned, duration: 60))
    }

    func testGeneratedSnapshotFromDifferentBaseDoesNotResumeProject() throws {
        let original = plainLyrics(["one", "two", "three"], source: "provider-a")
        var project = try TapSyncProject(track: makeTrack(duration: 60), lyrics: original)
        try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 4)
        var changedText = try project.syncedSnapshot()
        changedText.lines[1].text = "different"
        XCTAssertFalse(project.matches(lyrics: changedText, duration: 60))

        var unrelated = try project.syncedSnapshot()
        unrelated.timingBaseFingerprint = plainLyrics(
            ["one", "different", "three"],
            source: "provider-b"
        ).timelineFingerprint(duration: 60)

        XCTAssertFalse(project.matches(lyrics: unrelated, duration: 60))
    }

    func testNoAnchorDoesNotGenerateMisleadingSyncedSnapshot() throws {
        let project = try makeProject(lines: ["one", "two"])

        XCTAssertThrowsError(try project.resolvedLines()) {
            XCTAssertEqual($0 as? TapSyncProjectError, .noAnchors)
        }
        XCTAssertThrowsError(try project.syncedSnapshot()) {
            XCTAssertEqual($0 as? TapSyncProjectError, .noAnchors)
        }
    }

    func testNextUnanchoredLineSkipsWhitespaceAndRecordedRows() throws {
        var project = try makeProject(lines: ["one", " ", "three", "four"])
        try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 20)

        XCTAssertEqual(project.nextUnanchoredLineIndex(), 0)
        XCTAssertEqual(project.nextUnanchoredLineIndex(after: 0), 3)
        XCTAssertNil(project.nextUnanchoredLineIndex(after: 3))
    }

    func testLegacyLyricsSnapshotDecodesWithoutTimingBaseFingerprint() throws {
        let data = Data(#"{"availability":"plain","lines":[],"plainLines":["one"],"source":"legacy"}"#.utf8)

        let decoded = try JSONDecoder().decode(LyricsSnapshot.self, from: data)

        XCTAssertNil(decoded.timingBaseFingerprint)
    }

    private func assertRecordError(
        _ expected: TapSyncProjectError,
        project: inout TapSyncProject,
        line: Int,
        time: TimeInterval,
        file: StaticString = #filePath,
        lineNumber: UInt = #line
    ) {
        XCTAssertThrowsError(
            try project.recordOrReplaceAnchor(lineIndex: line, playbackTime: time),
            file: file,
            line: lineNumber
        ) {
            XCTAssertEqual($0 as? TapSyncProjectError, expected, file: file, line: lineNumber)
        }
    }

    private func assertMonotonic(
        _ lines: [LyricLine],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for pair in zip(lines, lines.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.time, pair.1.time, file: file, line: line)
        }
    }

    private func makeProject(
        lines: [String],
        duration: TimeInterval = 120
    ) throws -> TapSyncProject {
        try TapSyncProject(
            track: makeTrack(duration: duration),
            lyrics: plainLyrics(lines)
        )
    }

    private func plainLyrics(_ lines: [String], source: String = "plain-provider") -> LyricsSnapshot {
        LyricsSnapshot(availability: .plain, plainLines: lines, source: source)
    }

    private func makeTrack(
        id: String? = "track-id",
        duration: TimeInterval = 120,
        source: MusicPlayerSource? = .spotify
    ) -> Track {
        Track(
            id: id,
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: duration,
            position: 0,
            isPlaying: true,
            source: source
        )
    }
}
