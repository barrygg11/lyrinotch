import XCTest
@testable import LyrinotchCore

private enum ProviderFailure: Error {
    case unavailable
}

private final class ProviderCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LyricsSourceKind] = []

    func append(_ value: LyricsSourceKind) {
        lock.withLock { values.append(value) }
    }

    var calls: [LyricsSourceKind] { lock.withLock { values } }
}

final class CompositeLyricsFetcherTests: XCTestCase {
    func testFallsBackAfterProviderThrows() async throws {
        let log = ProviderCallLog()
        let fetcher = CompositeLyricsFetcher(
            preference: .lrclibThenAppleMusic,
            playerSource: .spotify,
            providerFetchOverride: { kind, _ in
                log.append(kind)
                if kind == .lrclib { throw ProviderFailure.unavailable }
                if kind == .netEase {
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: [LyricLine(time: 1, text: "hello")],
                        source: "netease",
                        detail: "Artist — Song"
                    )
                }
                return LyricsSnapshot(availability: .notFound, source: kind.rawValue)
            }
        )

        let result = try await fetcher.fetch(for: track)

        XCTAssertEqual(result.source, "netease")
        XCTAssertEqual(result.selectionReason, .fallbackSource)
        XCTAssertEqual(log.calls.prefix(2), [.lrclib, .netEase])
    }

    func testThrowsOnlyWhenEveryAttemptedProviderFails() async {
        let fetcher = CompositeLyricsFetcher(
            preference: .allOnline,
            playerSource: .spotify,
            providerFetchOverride: { _, _ in throw ProviderFailure.unavailable }
        )

        do {
            _ = try await fetcher.fetch(for: track)
            XCTFail("Expected allProvidersFailed")
        } catch let error as CompositeLyricsError {
            guard case .allProvidersFailed(let failures) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(failures.count, 3)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSyncedOnlineLyricsBeatEarlierAppleMusicPlainText() async throws {
        let log = ProviderCallLog()
        let fetcher = CompositeLyricsFetcher(
            preference: .appleMusicThenLRCLIB,
            playerSource: .appleMusic,
            providerFetchOverride: { kind, _ in
                log.append(kind)
                if kind == .appleMusic {
                    return LyricsSnapshot(
                        availability: .plain,
                        plainLines: ["plain"],
                        source: "apple-music"
                    )
                }
                if kind == .lrclib {
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: [LyricLine(time: 1, text: "timed")],
                        source: "lrclib"
                    )
                }
                return LyricsSnapshot(availability: .notFound, source: kind.rawValue)
            }
        )

        let result = try await fetcher.fetch(for: track)

        XCTAssertEqual(result.source, "lrclib")
        XCTAssertEqual(result.availability, .synced)
        XCTAssertEqual(Array(log.calls.prefix(2)), [.appleMusic, .lrclib])
    }

    func testStructuredProviderIdentityOverridesMisleadingDetailText() async throws {
        let fetcher = CompositeLyricsFetcher(
            preference: .netEaseFirst,
            playerSource: .spotify,
            providerFetchOverride: { kind, _ in
                if kind == .netEase {
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: [LyricLine(time: 1, text: "wrong")],
                        source: "netease",
                        detail: "Artist — Song",
                        matchedTrack: LyricsMatchMetadata(
                            title: "Different Song",
                            artist: "Different Artist",
                            duration: 260
                        )
                    )
                }
                if kind == .lrclib {
                    return LyricsSnapshot(
                        availability: .plain,
                        plainLines: ["right"],
                        source: "lrclib"
                    )
                }
                return LyricsSnapshot(availability: .notFound, source: kind.rawValue)
            }
        )

        let result = try await fetcher.fetch(for: track)

        XCTAssertEqual(result.source, "lrclib")
    }

    func testSmartPipelineUsesPlayerAndMetadataScript() {
        let western = Track(
            id: "western",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )
        let japanese = Track(
            id: "jp",
            name: "夜に駆ける",
            artist: "YOASOBI",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        XCTAssertEqual(
            LyricsSourcePreference.smartAutomatic.pipeline(
                for: western,
                playerSource: .spotify
            ),
            [.lrclib, .lyricsOvh, .netEase]
        )
        XCTAssertEqual(
            LyricsSourcePreference.smartAutomatic.pipeline(
                for: japanese,
                playerSource: .spotify
            ),
            [.lrclib, .netEase, .lyricsOvh]
        )
        XCTAssertEqual(
            LyricsSourcePreference.smartAutomatic.pipeline(
                for: japanese,
                playerSource: .appleMusic
            ).first,
            .appleMusic
        )
    }

    func testSmartSelectionPrefersMatchingJapaneseBody() async throws {
        let japaneseTrack = Track(
            id: "jp",
            name: "夜に駆ける",
            artist: "YOASOBI",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )
        let fetcher = CompositeLyricsFetcher(
            preference: .smartAutomatic,
            playerSource: .spotify,
            providerFetchOverride: { kind, _ in
                switch kind {
                case .lrclib:
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: [LyricLine(time: 1, text: "Running through the night")],
                        source: "lrclib"
                    )
                case .netEase:
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: [LyricLine(time: 1, text: "沈むように溶けてゆくように")],
                        source: "netease",
                        matchedTrack: LyricsMatchMetadata(
                            title: japaneseTrack.name,
                            artist: japaneseTrack.artist,
                            duration: japaneseTrack.duration
                        )
                    )
                default:
                    return LyricsSnapshot(availability: .notFound, source: kind.rawValue)
                }
            }
        )

        let result = try await fetcher.fetch(for: japaneseTrack)

        XCTAssertEqual(result.source, "netease")
        XCTAssertEqual(result.selectionReason, .languageMatch)
    }

    func testLegacyDuplicatePreferencesNormalizeToSmartMode() {
        XCTAssertEqual(
            LyricsSourcePreference.appleMusicThenLRCLIB.normalizedForSettings,
            .smartAutomatic
        )
        XCTAssertEqual(
            LyricsSourcePreference.lrclibThenAppleMusic.normalizedForSettings,
            .smartAutomatic
        )
        XCTAssertEqual(
            LyricsSourcePreference.allOnline.normalizedForSettings,
            .smartAutomatic
        )
        XCTAssertEqual(
            LyricsSourcePreference.maximumCoverage.normalizedForSettings,
            .maximumCoverage
        )
    }

    private var track: Track {
        Track(
            id: "track",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )
    }
}
