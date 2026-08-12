import XCTest
@testable import LyrinotchCore

final class LyricTimelineAlignerTests: XCTestCase {
    func testDurationScalePreservesShortLRC() {
        // A short timeline may simply have a long outro; do not invent drift.
        let lines = (0..<10).map { i in
            LyricLine(time: Double(i) * 12, text: "line \(i)")
        }
        let scaled = LyricTimelineAligner.durationScale(lines: lines, trackDuration: 200)
        XCTAssertEqual(scaled.scale, 1, accuracy: 0.001)
        XCTAssertEqual(scaled.lines, lines)
    }

    func testDurationScaleLeavesHealthyLRC() {
        let lines = (0..<10).map { i in
            LyricLine(time: Double(i) * 18, text: "line \(i)") // last ~162 / 180 = 0.9
        }
        let scaled = LyricTimelineAligner.durationScale(lines: lines, trackDuration: 180)
        XCTAssertEqual(scaled.scale, 1, accuracy: 0.001)
    }

    func testDurationScaleCompressesTimelineBeyondTrack() {
        let lines = (0..<10).map { i in
            LyricLine(time: Double(i) * 24, text: "line \(i)") // last 216 / track 180
        }
        let scaled = LyricTimelineAligner.durationScale(lines: lines, trackDuration: 180)
        XCTAssertLessThan(scaled.scale, 1)
        XCTAssertEqual(scaled.lines.last?.time ?? 0, 172.8, accuracy: 0.05)
    }

    func testAlignDoesNotInferOffsetFromUnevenLyricDensity() {
        let lines = [
            LyricLine(time: 8, text: "verse"),
            LyricLine(time: 12, text: "verse"),
            LyricLine(time: 16, text: "verse"),
            LyricLine(time: 20, text: "verse"),
            LyricLine(time: 140, text: "after instrumental"),
            LyricLine(time: 150, text: "outro")
        ]
        let early = LyricTimelineAligner.align(
            lines: lines,
            trackDuration: 180,
            playbackPosition: 30
        )
        let late = LyricTimelineAligner.align(
            lines: lines,
            trackDuration: 180,
            playbackPosition: 120
        )
        XCTAssertEqual(early, late)
        XCTAssertEqual(early.lines, lines)
    }

    func testEmbeddedOffsetParsed() {
        let lrc = """
        [offset:2000]
        [00:01.00]hello
        [00:02.00]world
        """
        XCTAssertEqual(LRCParser.embeddedOffsetSeconds(in: lrc), 2.0, accuracy: 0.001)
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines[0].time, 3.0, accuracy: 0.01) // 1 + 2
        XCTAssertEqual(lines[1].time, 4.0, accuracy: 0.01)
    }

    func testAlignCompressesOnlyOnce() {
        let lines = (0..<10).map { i in
            LyricLine(time: Double(i) * 24, text: "l\(i)") // last 216, track 180
        }
        let first = LyricTimelineAligner.align(
            lines: lines,
            trackDuration: 180,
            playbackPosition: 100
        )
        let second = LyricTimelineAligner.align(
            lines: first.lines,
            trackDuration: 180,
            playbackPosition: 120
        )
        XCTAssertLessThan(first.scale, 1)
        XCTAssertTrue(first.method.contains("scale"))
        XCTAssertEqual(second.scale, 1, accuracy: 0.001)
        XCTAssertEqual(second.lines, first.lines)
    }
}
