import XCTest
@testable import LyrinotchCore

private struct AppleLyricsStubExecutor: AppleScriptExecuting {
    var result: Result<String, Error>

    func run(script: String) async throws -> String {
        _ = script
        return try result.get()
    }
}

final class AppleMusicLyricsFetcherTests: XCTestCase {
    func testReturnsPlainLyricsWithValidatedTrackIdentity() async throws {
        let payload = [
            "OK", "music-id", "Song", "Artist", "180", "first\nsecond"
        ].joined(separator: MusicAppleScript.fieldSeparator)
        let fetcher = AppleMusicLyricsFetcher(
            executor: AppleLyricsStubExecutor(result: .success(payload))
        )

        let snapshot = try await fetcher.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .plain)
        XCTAssertEqual(snapshot.plainLines, ["first", "second"])
        XCTAssertEqual(snapshot.matchedTrack?.providerID, "music-id")
    }

    func testRejectsLyricsWhenCurrentTrackChanged() async throws {
        let payload = [
            "OK", "different-id", "Other Song", "Other Artist", "220", "wrong lyrics"
        ].joined(separator: MusicAppleScript.fieldSeparator)
        let fetcher = AppleMusicLyricsFetcher(
            executor: AppleLyricsStubExecutor(result: .success(payload))
        )

        let snapshot = try await fetcher.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .notFound)
        XCTAssertTrue(snapshot.detail?.contains("changed") == true)
    }

    func testParsesEmbeddedLRCAsSyncedLyrics() async throws {
        let lrc = "[00:01.00]first\n[00:02.00]second"
        let payload = [
            "OK", "music-id", "Song", "Artist", "180", lrc
        ].joined(separator: MusicAppleScript.fieldSeparator)
        let fetcher = AppleMusicLyricsFetcher(
            executor: AppleLyricsStubExecutor(result: .success(payload))
        )

        let snapshot = try await fetcher.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .synced)
        XCTAssertEqual(snapshot.lines.count, 2)
    }

    func testSurfacesAppleScriptPayloadErrors() async {
        let payload = ["ERROR", "Automation denied"]
            .joined(separator: MusicAppleScript.fieldSeparator)
        let fetcher = AppleMusicLyricsFetcher(
            executor: AppleLyricsStubExecutor(result: .success(payload))
        )

        do {
            _ = try await fetcher.fetch(for: track)
            XCTFail("Expected AppleMusicLyricsError")
        } catch let error as AppleMusicLyricsError {
            XCTAssertEqual(error, .script("Automation denied"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private var track: Track {
        Track(
            id: "music-id",
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 30,
            isPlaying: true
        )
    }
}
