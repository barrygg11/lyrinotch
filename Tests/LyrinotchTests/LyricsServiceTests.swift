import XCTest
@testable import LyrinotchCore

private final class ManualSearchRequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func reset() {
        lock.withLock { requests = [] }
    }

    var hosts: [String] {
        lock.withLock { requests.compactMap { $0.url?.host } }
    }
}

private final class ManualSearchURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = ManualSearchRequestStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.store.record(request)
        let data: Data
        if request.url?.host == "music.163.com" {
            data = Data(#"{"result":{"songs":[]}}"#.utf8)
        } else {
            data = Data("[]".utf8)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct StubFetcher: LyricsFetching {
    var result: Result<LyricsSnapshot, Error>
    var callCount = 0
    // class wrapper for mutation in async
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.withLock { value += 1 }
        }

        var count: Int { lock.withLock { value } }
    }
    private let counter = Counter()
    private let delayNanoseconds: UInt64

    init(result: Result<LyricsSnapshot, Error>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    var calls: Int { counter.count }

    func fetch(for track: Track) async throws -> LyricsSnapshot {
        _ = track
        counter.increment()
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

/// Deterministic provider stand-in used to exercise cache invalidation while
/// real fetch work is suspended. It returns real `LyricsSnapshot` values and
/// observes cancellation in the same place a network fetch would.
private actor GatedLyricsFetcher: LyricsFetching {
    private var startedIDs = Set<String>()
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]

    func fetch(for track: Track) async throws -> LyricsSnapshot {
        let id = track.id ?? track.name
        startedIDs.insert(id)
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    continuations[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.resume(id) }
        }
        try Task.checkCancellation()
        return LyricsSnapshot(
            availability: .synced,
            lines: [LyricLine(time: 1, text: "provider-\(id)")],
            source: "gated"
        )
    }

    func waitUntilStarted(_ id: String) async {
        while !startedIDs.contains(id) {
            await Task.yield()
        }
    }

    func resume(_ id: String) {
        continuations.removeValue(forKey: id)?.resume()
    }
}

private actor LyricsServiceOperationGate {
    private var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !suspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class LyricsServiceTests: XCTestCase {
    func testManualSearchProviderOrderFollowsPreference() {
        XCTAssertEqual(
            LyricsService.manualSearchProviders(for: .lrclibOnly),
            [.lrclib]
        )
        XCTAssertEqual(
            LyricsService.manualSearchProviders(for: .netEaseFirst),
            [.netEase, .lrclib]
        )
        XCTAssertEqual(
            LyricsService.manualSearchProviders(for: .smartAutomatic),
            [.lrclib, .netEase]
        )
    }

    func testManualSearchStopsContactingNetEaseWhenPreferenceChangesToLRCLIBOnly() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManualSearchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = LyricsService(
            preference: .netEaseFirst,
            lrclib: LRCLIBClient(
                session: session,
                baseURL: URL(string: "https://lrclib.test/api")!
            ),
            netEase: NetEaseLyricsClient(session: session)
        )

        ManualSearchURLProtocol.store.reset()
        _ = try await service.search(query: "Song Artist")
        XCTAssertEqual(
            Set(ManualSearchURLProtocol.store.hosts),
            Set(["lrclib.test", "music.163.com"])
        )

        await service.setPreference(.lrclibOnly)
        ManualSearchURLProtocol.store.reset()
        _ = try await service.search(query: "Song Artist")
        XCTAssertEqual(ManualSearchURLProtocol.store.hosts, ["lrclib.test"])
    }

    func testCachesSuccessfulFetch() async {
        let fetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "hi")],
                    source: "stub"
                )
            )
        )
        let service = LyricsService(fetcher: fetcher)
        let track = Track(
            id: "spotify:track:1",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 100,
            position: 0,
            isPlaying: true
        )

        let a = await service.snapshot(for: track)
        let b = await service.snapshot(for: track)
        XCTAssertEqual(a.availability, .synced)
        XCTAssertEqual(b.lines.first?.text, "hi")
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testCacheKeepsSameCatalogIDSeparateAcrossPlayers() async {
        let fetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "hi")],
                    source: "stub"
                )
            )
        )
        let service = LyricsService(fetcher: fetcher)
        let spotify = Track(
            id: "shared-id",
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: 100,
            position: 0,
            isPlaying: true,
            source: .spotify
        )
        var appleMusic = spotify
        appleMusic.source = .appleMusic

        _ = await service.snapshot(for: spotify)
        _ = await service.snapshot(for: appleMusic)
        _ = await service.snapshot(for: spotify)

        XCTAssertEqual(fetcher.calls, 2)
    }

    func testSuccessfulCacheUsesLRUEvictionBound() async {
        let fetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "line")],
                    source: "stub"
                )
            )
        )
        let service = LyricsService(fetcher: fetcher, maximumCacheEntries: 2)
        let first = makeTrack(id: "cache-1")
        let second = makeTrack(id: "cache-2")
        let third = makeTrack(id: "cache-3")

        _ = await service.snapshot(for: first)
        _ = await service.snapshot(for: second)
        // Touch first, making second the least-recently used entry.
        _ = await service.snapshot(for: first)
        _ = await service.snapshot(for: third)
        _ = await service.snapshot(for: second)

        XCTAssertEqual(fetcher.calls, 4)
    }

    func testSkippedWhenMetadataMissing() async {
        let fetcher = StubFetcher(
            result: .success(LyricsSnapshot(availability: .synced, lines: []))
        )
        let service = LyricsService(fetcher: fetcher)
        let snap = await service.snapshot(for: .empty)
        XCTAssertEqual(snap.availability, .skipped)
        XCTAssertEqual(fetcher.calls, 0)
    }

    func testMapsFetcherError() async {
        let fetcher = StubFetcher(result: .failure(LRCLIBError.httpStatus(500)))
        let service = LyricsService(fetcher: fetcher)
        let track = Track(
            id: nil,
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: nil,
            position: nil,
            isPlaying: false
        )
        let snap = await service.snapshot(for: track)
        XCTAssertEqual(snap.availability, .error)
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testCoalescesConcurrentFetchesForSameTrack() async {
        let fetcher = StubFetcher(
            result: .success(LyricsSnapshot(availability: .notFound)),
            delayNanoseconds: 100_000_000
        )
        let service = LyricsService(fetcher: fetcher)
        let track = makeTrack()

        async let first = service.snapshot(for: track)
        async let second = service.snapshot(for: track)
        let snapshots = await [first, second]

        XCTAssertEqual(snapshots.map(\.availability), [.notFound, .notFound])
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testManualSelectionForOneTrackDoesNotCancelAnotherTracksFetch() async {
        let fetcher = GatedLyricsFetcher()
        let service = LyricsService(fetcher: fetcher, pinnedLyricsStore: .ephemeral())
        let manualTrack = makeTrack(id: "manual-a")
        let fetchingTrack = makeTrack(id: "fetching-b")
        let fetchingTask = Task { await service.snapshot(for: fetchingTrack) }
        await fetcher.waitUntilStarted("fetching-b")

        let hit = LyricsSearchHit(
            id: "manual-a-hit",
            trackName: manualTrack.name,
            artistName: manualTrack.artist,
            hasSynced: true,
            sourceLabel: "Test",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "chosen-a")],
                source: "test"
            )
        )
        _ = await service.apply(hit: hit, to: manualTrack)
        await fetcher.resume("fetching-b")
        let fetched = await fetchingTask.value

        XCTAssertEqual(fetched.availability, .synced)
        XCTAssertEqual(fetched.lines.first?.text, "provider-fetching-b")
    }

    func testLateProviderResultForSameTrackReturnsManualSelection() async {
        let fetcher = GatedLyricsFetcher()
        let service = LyricsService(fetcher: fetcher, pinnedLyricsStore: .ephemeral())
        let track = makeTrack(id: "same-track")
        let fetchingTask = Task { await service.snapshot(for: track) }
        await fetcher.waitUntilStarted("same-track")

        let hit = LyricsSearchHit(
            id: "same-track-hit",
            trackName: track.name,
            artistName: track.artist,
            hasSynced: true,
            sourceLabel: "Test",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "chosen-manually")],
                source: "test"
            )
        )
        let applied = await service.apply(hit: hit, to: track)
        await fetcher.resume("same-track")
        let originalCallerResult = await fetchingTask.value
        let subsequentResult = await service.snapshot(for: track)

        XCTAssertEqual(applied.lines.first?.text, "chosen-manually")
        XCTAssertEqual(originalCallerResult.lines.first?.text, "chosen-manually")
        XCTAssertEqual(subsequentResult.lines.first?.text, "chosen-manually")
    }

    func testEveryCoalescedWaiterReceivesManualWinnerAfterInvalidation() async {
        let fetcher = GatedLyricsFetcher()
        let service = LyricsService(fetcher: fetcher, pinnedLyricsStore: .ephemeral())
        let track = makeTrack(id: "coalesced-manual")
        let firstWaiter = Task { await service.snapshot(for: track) }
        await fetcher.waitUntilStarted("coalesced-manual")
        let secondWaiter = Task { await service.snapshot(for: track) }
        for _ in 0..<20 { await Task.yield() }

        let hit = LyricsSearchHit(
            id: "coalesced-hit",
            trackName: track.name,
            artistName: track.artist,
            hasSynced: true,
            sourceLabel: "Test",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "coalesced-winner")],
                source: "test"
            )
        )
        _ = await service.apply(hit: hit, to: track)
        await fetcher.resume("coalesced-manual")
        let first = await firstWaiter.value
        let second = await secondWaiter.value

        XCTAssertEqual(first.lines.first?.text, "coalesced-winner")
        XCTAssertEqual(second.lines.first?.text, "coalesced-winner")
    }

    func testCanceledManualApplyDoesNotCreatePersistentPin() async {
        let gate = LyricsServiceOperationGate()
        let automaticFetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "automatic")],
                    source: "stub"
                )
            )
        )
        let service = LyricsService(
            fetcher: automaticFetcher,
            pinnedLyricsStore: .ephemeral()
        )
        let track = makeTrack(id: "canceled-manual")
        let hit = LyricsSearchHit(
            id: "canceled-hit",
            trackName: track.name,
            artistName: track.artist,
            hasSynced: true,
            sourceLabel: "Test",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "superseded-manual")],
                source: "test"
            )
        )
        let canceledApply = Task {
            await gate.suspend()
            return await service.apply(hit: hit, to: track)
        }
        await gate.waitUntilSuspended()

        canceledApply.cancel()
        await gate.resume()
        _ = await canceledApply.value
        let fetched = await service.snapshot(for: track)

        XCTAssertEqual(fetched.lines.first?.text, "automatic")
        XCTAssertEqual(automaticFetcher.calls, 1)
    }

    func testNotFoundCacheExpires() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let fetcher = StubFetcher(result: .success(LyricsSnapshot(availability: .notFound)))
        let service = LyricsService(
            fetcher: fetcher,
            notFoundCacheTTL: 10,
            now: { clock.now }
        )
        let track = makeTrack()

        _ = await service.snapshot(for: track)
        _ = await service.snapshot(for: track)
        XCTAssertEqual(fetcher.calls, 1)

        clock.advance(by: 11)
        _ = await service.snapshot(for: track)
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testActiveTextHelper() {
        let snap = LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 10, text: " first "),
                LyricLine(time: 20, text: "second")
            ]
        )
        XCTAssertNil(snap.activeText(at: 5))
        XCTAssertEqual(snap.activeText(at: 10), "first")
        XCTAssertEqual(snap.activeText(at: 25), "second")
    }

    func testPreservesShortSyncedTimeline() async {
        let lines = (0..<10).map {
            LyricLine(time: Double($0) * 10, text: "line \($0)")
        }
        let fetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(availability: .synced, lines: lines, source: "stub")
            )
        )
        let service = LyricsService(fetcher: fetcher)
        let track = Track(
            id: "short-timeline",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 200,
            position: 100,
            isPlaying: true
        )

        let snapshot = await service.snapshot(for: track)

        XCTAssertEqual(snapshot.lines, lines)
    }

    func testCompressesOverlongTimelineOnceAcrossCacheHits() async {
        let lines = (0..<10).map {
            LyricLine(time: Double($0) * 24, text: "line \($0)")
        }
        let fetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(availability: .synced, lines: lines, source: "stub")
            )
        )
        let service = LyricsService(fetcher: fetcher)
        let track = Track(
            id: "overlong-timeline",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 90,
            isPlaying: true
        )

        let first = await service.snapshot(for: track)
        let second = await service.snapshot(for: track)

        XCTAssertEqual(first.lines.last?.time ?? 0, 172.8, accuracy: 0.05)
        XCTAssertEqual(second.lines, first.lines)
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testManualSearchHitReturnsAndCachesAlignedSnapshot() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let service = LyricsService(
            fetcher: StubFetcher(result: .success(.skipped)),
            pinnedLyricsStore: pinnedStore
        )
        let track = Track(
            id: "manual-overlong",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 90,
            isPlaying: true
        )
        let lines = (0..<10).map {
            LyricLine(time: Double($0) * 24, text: "line \($0)")
        }
        let hit = LyricsSearchHit(
            id: "manual-hit",
            trackName: "Song",
            artistName: "Artist",
            hasSynced: true,
            sourceLabel: "Test",
            snapshot: LyricsSnapshot(availability: .synced, lines: lines, source: "test")
        )

        let applied = await service.apply(hit: hit, to: track)
        let cached = await service.snapshot(for: track)

        XCTAssertEqual(applied.lines.last?.time ?? 0, 172.8, accuracy: 0.05)
        XCTAssertEqual(cached, applied)
        XCTAssertEqual(applied.selectionReason, .manuallySelected)
    }

    func testManualSelectionPersistsUntilRemoved() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let track = makeTrack()
        let hit = LyricsSearchHit(
            id: "manual-persist",
            trackName: track.name,
            artistName: track.artist,
            hasSynced: true,
            sourceLabel: "LRCLIB",
            snapshot: LyricsSnapshot(
                availability: .synced,
                lines: [LyricLine(time: 1, text: "chosen")],
                source: "lrclib"
            )
        )
        let firstService = LyricsService(
            fetcher: StubFetcher(result: .success(.skipped)),
            pinnedLyricsStore: pinnedStore
        )
        _ = await firstService.apply(hit: hit, to: track)

        let automaticFetcher = StubFetcher(
            result: .success(
                LyricsSnapshot(
                    availability: .synced,
                    lines: [LyricLine(time: 1, text: "automatic")],
                    source: "stub"
                )
            )
        )
        let secondService = LyricsService(
            fetcher: automaticFetcher,
            pinnedLyricsStore: pinnedStore
        )

        let pinned = await secondService.snapshot(for: track)
        XCTAssertEqual(pinned.lines.first?.text, "chosen")
        XCTAssertEqual(pinned.selectionReason, .manuallySelected)
        XCTAssertEqual(automaticFetcher.calls, 0)

        await secondService.removePinnedLyrics(for: track)
        let automatic = await secondService.snapshot(for: track)
        XCTAssertEqual(automatic.lines.first?.text, "automatic")
        XCTAssertEqual(automaticFetcher.calls, 1)
    }

    func testManualMutationUsesCapturedPlayerNamespace() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let service = LyricsService(pinnedLyricsStore: pinnedStore)
        let track = makeTrack(id: "captured-source")
        let selected = LyricsSnapshot(
            availability: .plain,
            plainLines: ["captured"],
            source: "manual"
        )
        await service.setPlayerSource(.appleMusic)

        _ = await service.apply(
            manualSnapshot: selected,
            to: track,
            source: .spotify
        )

        XCTAssertNotNil(pinnedStore.snapshot(for: track, source: .spotify))
        XCTAssertNil(pinnedStore.snapshot(for: track, source: .appleMusic))

        await service.removePinnedLyrics(for: track, source: .spotify)

        XCTAssertNil(pinnedStore.snapshot(for: track, source: .spotify))
    }

    func testPlainLyricsEstimatedTimeline() {
        let snap = LyricsSnapshot(
            availability: .plain,
            plainLines: ["一行", "二行", "三行", "四行"]
        )
        let lines = snap.displayLines(duration: 100)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].time, 0, accuracy: 0.01)
        XCTAssertEqual(lines[1].time, 25, accuracy: 0.01)
        XCTAssertEqual(snap.activeText(at: 10, duration: 100), "一行")
        XCTAssertEqual(snap.activeText(at: 60, duration: 100), "三行")
    }

    private func makeTrack(id: String = "test-track") -> Track {
        Track(
            id: id,
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date { lock.withLock { value } }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}
