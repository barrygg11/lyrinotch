import XCTest
@testable import LyrinotchCore

final class LRCParserTests: XCTestCase {
    func testParsesBasicLines() {
        let lrc = """
        [ar:Artist]
        [ti:Title]
        [00:14.06] I don't show much
        [00:17.47] When I'm around you
        [01:02.5] Later line
        """

        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "I don't show much")
        XCTAssertEqual(lines[0].time, 14.06, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 17.47, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 62.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].text, "Later line")
    }

    func testMultipleTimestampsOnOneLine() {
        let lrc = "[00:10.00][00:20.00] Chorus"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time, 10, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 20, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Chorus")
        XCTAssertEqual(lines[1].text, "Chorus")
    }

    func testSortsOutOfOrder() {
        let lrc = """
        [00:30.00] Second
        [00:10.00] First
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.text), ["First", "Second"])
    }

    func testEmptyAndNoise() {
        XCTAssertTrue(LRCParser.parse("").isEmpty)
        XCTAssertTrue(LRCParser.parse("no timestamps here").isEmpty)
    }

    func testRejectsUnrealisticEmbeddedOffset() {
        let lrc = "[offset:999999999999999999999999]\n[00:01.00] line"

        XCTAssertEqual(LRCParser.embeddedOffsetSeconds(in: lrc), 0)
        XCTAssertTrue(LRCParser.parse(lrc).isEmpty)
    }

    func testRejectsUnparseableEmbeddedOffsetDigits() {
        let lrc = "[offset:\(String(repeating: "9", count: 1_000))]\n[00:01.00] line"

        XCTAssertTrue(LRCParser.parse(lrc).isEmpty)
    }

    func testActiveIndexWithParsedLines() {
        let lines = LRCParser.parse("""
        [00:10.00] A
        [00:20.00] B
        """)
        XCTAssertNil(LyricLine.activeIndex(in: lines, at: 5))
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 10), 0)
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 19.9), 0)
        XCTAssertEqual(LyricLine.activeIndex(in: lines, at: 20), 1)
    }
}
