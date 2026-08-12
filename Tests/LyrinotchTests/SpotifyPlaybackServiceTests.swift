import XCTest
@testable import LyrinotchCore

private struct ScriptStub: SpotifyScriptExecuting {
    var result: Result<String, Error>

    func run(script: String) async throws -> String {
        _ = script
        return try result.get()
    }
}

final class SpotifyPlaybackServiceTests: XCTestCase {
    func testPlayPauseOK() async throws {
        let service = SpotifyPlaybackService(executor: ScriptStub(result: .success("OK")))
        try await service.playPause()
    }

    func testNotRunning() async {
        let service = SpotifyPlaybackService(executor: ScriptStub(result: .success("NOT_RUNNING")))
        do {
            try await service.nextTrack()
            XCTFail("expected error")
        } catch let error as SpotifyPlaybackService.PlaybackError {
            XCTAssertEqual(error, .playerNotRunning)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
