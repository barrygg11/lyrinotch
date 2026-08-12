import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class AppDiagnosticsTests: XCTestCase {
    func testRingBufferIsBoundedAndExportsOnlyOperationalFields() {
        let diagnostics = AppDiagnostics(capacity: 3)
        for latency in 1...5 {
            diagnostics.recordPlayback(
                availability: .ready,
                source: .spotify,
                latencyMilliseconds: latency
            )
        }

        let text = diagnostics.recentText(limit: 10)
        XCTAssertEqual(diagnostics.recentEventCount, 3)
        XCTAssertTrue(text.contains("availability=ready"))
        XCTAssertTrue(text.contains("latency_ms=5"))
        XCTAssertFalse(text.contains("latency_ms=1"))
    }

    func testProviderLabelIsSanitizedBeforeExport() {
        let diagnostics = AppDiagnostics(capacity: 2)
        diagnostics.recordLyrics(
            availability: .synced,
            source: "LRCLIB Song Title / Secret",
            lineCount: 10,
            latencyMilliseconds: 20
        )

        let text = diagnostics.recentText()
        XCTAssertTrue(text.contains("provider=unknown"))
        XCTAssertFalse(text.contains("LRCLIB Song Title / Secret"))
        XCTAssertFalse(text.lowercased().contains("secret"))
    }
}
