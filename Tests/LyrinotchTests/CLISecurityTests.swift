import XCTest
@testable import Lyrinotch

final class CLISecurityTests: XCTestCase {
    func testTerminalControlsAreEscapedButUnicodeIsPreserved() {
        let input = "歌詞\u{1B}[2J\u{1B}]52;c;secret\u{07}\r\n下一行"

        let output = CLIRunner.sanitizeTerminalText(input)

        XCTAssertFalse(output.contains("\u{1B}"))
        XCTAssertFalse(output.contains("\u{07}"))
        XCTAssertTrue(output.contains("歌詞"))
        XCTAssertTrue(output.contains("下一行"))
        XCTAssertTrue(output.contains("\\u{1B}"))
    }
}
