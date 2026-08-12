import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class LyricsSearchStateTests: XCTestCase {
    @MainActor
    func testChangedQueryClearsSearchingWhenOriginalRequestFinishes() async {
        let requests = SearchRequestGate()
        let state = LyricsSearchState()
        state.query = "first query"

        state.run(search: { query in
            await requests.results(for: query)
        })
        await requests.waitUntilStarted("first query")

        state.query = "changed query"
        await requests.complete("first query")

        await waitUntil { !state.isSearching }
        XCTAssertFalse(state.isSearching)
        XCTAssertTrue(state.hits.isEmpty)
    }

    @MainActor
    func testOlderRequestCannotClearNewerSearchState() async {
        let requests = SearchRequestGate()
        let state = LyricsSearchState()
        state.query = "first query"
        state.run(search: { query in
            await requests.results(for: query)
        })
        await requests.waitUntilStarted("first query")

        state.query = "second query"
        state.run(search: { query in
            await requests.results(for: query)
        })
        await requests.waitUntilStarted("second query")

        await requests.complete("first query")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(state.isSearching)

        await requests.complete("second query")
        await waitUntil { !state.isSearching }
        XCTAssertFalse(state.isSearching)
    }

    @MainActor
    func testTrackChangeInvalidatesOldResultsAndRetargetsSearch() {
        let state = LyricsSearchState()
        let oldTrack = makeTrack(id: "old", name: "Old Song")
        let newTrack = makeTrack(id: "new", name: "New Song")
        state.prepare(for: oldTrack, trackKey: "old-key")
        state.hits = [makeHit(id: "old-hit")]

        state.trackDidChange(to: newTrack, trackKey: "new-key")

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.targetTrackKey, "new-key")
        XCTAssertEqual(state.query, "Artist New Song")
        XCTAssertTrue(state.hits.isEmpty)
        XCTAssertEqual(state.error, L10n.t("search.track_changed"))
        XCTAssertFalse(state.canApply(to: "old-key"))
        XCTAssertTrue(state.canApply(to: "new-key"))
    }

    @MainActor
    func testClosingSearchClearsTargetIdentity() {
        let state = LyricsSearchState()
        state.prepare(for: makeTrack(id: "song", name: "Song"), trackKey: "song-key")

        state.stop()

        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.targetTrackKey)
        XCTAssertFalse(state.canApply(to: "song-key"))
    }

    private func makeTrack(id: String, name: String) -> Track {
        Track(
            id: id,
            name: name,
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 0,
            isPlaying: true
        )
    }

    private func makeHit(id: String) -> LyricsSearchHit {
        LyricsSearchHit(
            id: id,
            trackName: "Song",
            artistName: "Artist",
            duration: 180,
            hasSynced: true,
            sourceLabel: "test",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "line")]
            )
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }
}

private actor SearchRequestGate {
    private var started = Set<String>()
    private var continuations: [String: CheckedContinuation<[LyricsSearchHit], Never>] = [:]

    func results(for query: String) async -> [LyricsSearchHit] {
        started.insert(query)
        return await withCheckedContinuation { continuation in
            continuations[query] = continuation
        }
    }

    func waitUntilStarted(_ query: String) async {
        while !started.contains(query) {
            await Task.yield()
        }
    }

    func complete(_ query: String, with hits: [LyricsSearchHit] = []) {
        continuations.removeValue(forKey: query)?.resume(returning: hits)
    }
}
