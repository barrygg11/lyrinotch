import Foundation

public enum LyricsSearchError: Error, LocalizedError, Sendable, Equatable {
    case allProvidersFailed([String])

    public var errorDescription: String? {
        switch self {
        case .allProvidersFailed(let failures):
            return "All lyrics search providers failed: " + failures.joined(separator: "; ")
        }
    }
}

/// Fetches and caches lyrics (multi-source via `CompositeLyricsFetcher` by default).
public actor LyricsService {
    private struct CacheEntry: Sendable {
        var snapshot: LyricsSnapshot
        var expiresAt: Date?
        var accessOrdinal: UInt64
    }

    private struct CacheGeneration: Equatable, Sendable {
        var global: UInt64
        var track: UInt64
    }

    private enum SearchProviderResult: Sendable {
        case success([LyricsSearchHit])
        case failure(String)
    }

    private struct IndexedSearchProviderResult: Sendable {
        var index: Int
        var provider: LyricsSourceKind
        var result: SearchProviderResult
    }

    private var preference: LyricsSourcePreference
    private var playerSource: MusicPlayerSource?
    private let lrclib: LRCLIBClient
    private let appleMusic = AppleMusicLyricsFetcher()
    private let netEase: NetEaseLyricsClient
    private let lyricsOvh = LyricsOvhClient()
    private let pinnedLyricsStore: PinnedLyricsStore
    /// Test / DI override — when set, used instead of the composite fetcher.
    private let overrideFetcher: (any LyricsFetching)?
    private let now: @Sendable () -> Date
    private let notFoundCacheTTL: TimeInterval
    private let errorCacheTTL: TimeInterval
    private let maximumCacheEntries: Int
    private var cache: [TrackIdentity: CacheEntry] = [:]
    private var inFlight: [TrackIdentity: Task<LyricsSnapshot, Never>] = [:]
    private var globalCacheGeneration: UInt64 = 0
    private var trackCacheGenerations: [TrackIdentity: UInt64] = [:]
    private var cacheAccessOrdinal: UInt64 = 0

    public init(
        preference: LyricsSourcePreference = .lrclibOnly,
        fetcher: (any LyricsFetching)? = nil,
        pinnedLyricsStore: PinnedLyricsStore = PinnedLyricsStore(),
        notFoundCacheTTL: TimeInterval = 300,
        errorCacheTTL: TimeInterval = 20,
        maximumCacheEntries: Int = 128,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.preference = preference
        self.lrclib = LRCLIBClient()
        self.netEase = NetEaseLyricsClient()
        self.overrideFetcher = fetcher
        self.pinnedLyricsStore = pinnedLyricsStore
        self.notFoundCacheTTL = max(0, notFoundCacheTTL)
        self.errorCacheTTL = max(0, errorCacheTTL)
        self.maximumCacheEntries = max(1, maximumCacheEntries)
        self.now = now
    }

    /// Internal dependency-injection initializer used by provider-routing tests.
    init(
        preference: LyricsSourcePreference,
        lrclib: LRCLIBClient,
        netEase: NetEaseLyricsClient,
        pinnedLyricsStore: PinnedLyricsStore = PinnedLyricsStore(),
        notFoundCacheTTL: TimeInterval = 300,
        errorCacheTTL: TimeInterval = 20,
        maximumCacheEntries: Int = 128,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.preference = preference
        self.lrclib = lrclib
        self.netEase = netEase
        self.overrideFetcher = nil
        self.pinnedLyricsStore = pinnedLyricsStore
        self.notFoundCacheTTL = max(0, notFoundCacheTTL)
        self.errorCacheTTL = max(0, errorCacheTTL)
        self.maximumCacheEntries = max(1, maximumCacheEntries)
        self.now = now
    }

    public func setPreference(_ preference: LyricsSourcePreference) {
        guard self.preference != preference else { return }
        self.preference = preference
        invalidateCache()
    }

    public func setPlayerSource(_ source: MusicPlayerSource?) {
        guard playerSource != source else { return }
        self.playerSource = source
        invalidateCache()
    }

    /// Full lyrics snapshot (cached per track identity).
    public func snapshot(for track: Track) async -> LyricsSnapshot {
        let name = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !artist.isEmpty else {
            return .skipped
        }

        let requestSource = playerSource
        if let pinned = pinnedLyricsStore.snapshot(for: track, source: requestSource) {
            return Self.applyTimelineAlignment(pinned, track: track)
        }

        let identity = TrackIdentity(track: track, source: requestSource)
        if var cached = cache[identity] {
            if cached.expiresAt.map({ $0 > now() }) ?? true {
                cached.accessOrdinal = nextCacheAccessOrdinal()
                cache[identity] = cached
                return cached.snapshot
            }
            cache[identity] = nil
        }
        if let task = inFlight[identity] {
            let result = await task.value
            if let pinned = pinnedLyricsStore.snapshot(for: track, source: requestSource) {
                return Self.applyTimelineAlignment(pinned, track: track)
            }
            return result
        }

        let fetcher: any LyricsFetching = overrideFetcher ?? CompositeLyricsFetcher(
            preference: preference,
            lrclib: lrclib,
            appleMusic: appleMusic,
            netEase: netEase,
            lyricsOvh: lyricsOvh,
            playerSource: playerSource
        )
        let generation = cacheGeneration(for: identity)
        let task = Task {
            do {
                let result = try await fetcher.fetch(for: track)
                return Self.applyTimelineAlignment(result, track: track)
            } catch {
                return LyricsSnapshot(
                    availability: .error,
                    detail: error.localizedDescription
                )
            }
        }
        inFlight[identity] = task
        let result = await task.value
        if generation == cacheGeneration(for: identity) {
            inFlight[identity] = nil
            cache[identity] = CacheEntry(
                snapshot: result,
                expiresAt: expiryDate(for: result),
                accessOrdinal: nextCacheAccessOrdinal()
            )
            trimCacheIfNeeded()
            return result
        }

        // A same-track manual selection may supersede this request while its
        // provider is suspended. Return the winning pinned timeline to the
        // original caller instead of surfacing the canceled provider result.
        if let pinned = pinnedLyricsStore.snapshot(for: track, source: requestSource) {
            return Self.applyTimelineAlignment(pinned, track: track)
        }
        return result
    }

    /// Compress an LRC only when its timestamps extend beyond the track.
    private static func applyTimelineAlignment(_ snap: LyricsSnapshot, track: Track) -> LyricsSnapshot {
        guard snap.availability == .synced, !snap.lines.isEmpty else { return snap }
        let aligned = LyricTimelineAligner.align(
            lines: snap.lines,
            trackDuration: track.duration
        )
        guard abs(aligned.scale - 1) > 0.02 else { return snap }
        var out = snap
        out.lines = aligned.lines
        let note = "align:\(aligned.method)"
        if let detail = out.detail, !detail.isEmpty {
            out.detail = detail + " · " + note
        } else {
            out.detail = note
        }
        return out
    }

    /// Timed lines only (empty when unavailable).
    public func lines(for track: Track) async -> [LyricLine] {
        let snap = await snapshot(for: track)
        return snap.lines
    }

    /// Manual search — queries the search-capable providers in the selected pipeline.
    public func search(query: String) async throws -> [LyricsSearchHit] {
        let providerKinds = Self.manualSearchProviders(for: preference)
        let lrclib = self.lrclib
        let netEase = self.netEase
        let results = await withTaskGroup(of: IndexedSearchProviderResult.self) { group in
            for (index, provider) in providerKinds.enumerated() {
                group.addTask {
                    let result = await Self.captureSearch {
                        switch provider {
                        case .lrclib:
                            return try await lrclib.searchHits(query: query)
                        case .netEase:
                            return try await netEase.searchHits(query: query)
                        case .appleMusic, .lyricsOvh:
                            return []
                        }
                    }
                    return IndexedSearchProviderResult(
                        index: index,
                        provider: provider,
                        result: result
                    )
                }
            }

            var collected: [IndexedSearchProviderResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.index < $1.index }
        }
        var hits: [LyricsSearchHit] = []
        var failures: [String] = []
        var successCount = 0
        for providerResult in results {
            switch providerResult.result {
            case .success(let providerHits):
                successCount += 1
                hits.append(contentsOf: providerHits)
            case .failure(let message):
                failures.append("\(Self.searchProviderName(providerResult.provider)): \(message)")
            }
        }
        if successCount == 0 {
            throw LyricsSearchError.allProvidersFailed(failures)
        }
        // Prefer timed lyrics but preserve each provider's relevance order.
        return hits.enumerated().sorted { lhs, rhs in
            if lhs.element.hasSynced != rhs.element.hasSynced {
                return lhs.element.hasSynced && !rhs.element.hasSynced
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Only LRCLIB and NetEase expose the free-text search used by the manual picker.
    /// Filtering the configured pipeline preserves both opt-outs and provider order.
    static func manualSearchProviders(
        for preference: LyricsSourcePreference
    ) -> [LyricsSourceKind] {
        preference.pipeline.reduce(into: []) { result, provider in
            guard provider == .lrclib || provider == .netEase,
                  !result.contains(provider)
            else { return }
            result.append(provider)
        }
    }

    /// Pin a user-picked search result into the cache for this track.
    @discardableResult
    public func apply(hit: LyricsSearchHit, to track: Track) -> LyricsSnapshot {
        apply(hit: hit, to: track, source: playerSource)
    }

    /// Source-stable form used by delayed UI mutations after the active player
    /// may already have changed.
    @discardableResult
    public func apply(
        hit: LyricsSearchHit,
        to track: Track,
        source: MusicPlayerSource?
    ) -> LyricsSnapshot {
        var selected = hit.snapshot
        selected.selectionReason = .manuallySelected
        return applyManuallySelectedSnapshot(selected, to: track, source: source)
    }

    /// Pin a validated local LRC import for this track without querying providers.
    @discardableResult
    public func apply(importedLRC: LocalLRCImportResult, to track: Track) -> LyricsSnapshot {
        apply(importedLRC: importedLRC, to: track, source: playerSource)
    }

    @discardableResult
    public func apply(
        importedLRC: LocalLRCImportResult,
        to track: Track,
        source: MusicPlayerSource?
    ) -> LyricsSnapshot {
        var selected = importedLRC.snapshot
        selected.selectionReason = .manuallySelected
        return applyManuallySelectedSnapshot(selected, to: track, source: source)
    }

    /// Pin a locally authored timeline such as Tap Sync output.
    @discardableResult
    public func apply(manualSnapshot: LyricsSnapshot, to track: Track) -> LyricsSnapshot {
        apply(manualSnapshot: manualSnapshot, to: track, source: playerSource)
    }

    @discardableResult
    public func apply(
        manualSnapshot: LyricsSnapshot,
        to track: Track,
        source: MusicPlayerSource?
    ) -> LyricsSnapshot {
        var selected = manualSnapshot
        selected.selectionReason = .manuallySelected
        return applyManuallySelectedSnapshot(selected, to: track, source: source)
    }

    private func applyManuallySelectedSnapshot(
        _ selected: LyricsSnapshot,
        to track: Track,
        source: MusicPlayerSource?
    ) -> LyricsSnapshot {
        let applied = Self.applyTimelineAlignment(selected, track: track)

        // A canceled caller must not cross this actor boundary and recreate a
        // local pin after a newer manual operation or Clear Data action.
        guard !Task.isCancelled else { return applied }

        let identity = TrackIdentity(track: track, source: source)
        invalidateCache(for: identity)
        pinnedLyricsStore.set(applied, for: track, source: identity.source)
        cache[identity] = CacheEntry(
            snapshot: applied,
            expiresAt: nil,
            accessOrdinal: nextCacheAccessOrdinal()
        )
        trimCacheIfNeeded()
        return applied
    }

    public func clearCache() {
        invalidateCache()
    }

    /// Removes lyrics that the user explicitly pinned and clears memory cache.
    public func clearStoredLyrics() {
        pinnedLyricsStore.clearAll()
        invalidateCache()
    }

    /// Return one manually pinned track to automatic provider selection.
    public func removePinnedLyrics(for track: Track) {
        removePinnedLyrics(for: track, source: playerSource)
    }

    /// Source-stable form used by delayed UI mutations after player changes.
    public func removePinnedLyrics(
        for track: Track,
        source: MusicPlayerSource?
    ) {
        pinnedLyricsStore.remove(for: track, source: source)
        cache[TrackIdentity(track: track, source: source)] = nil
    }

    private func expiryDate(for snapshot: LyricsSnapshot) -> Date? {
        let ttl: TimeInterval?
        switch snapshot.availability {
        case .notFound:
            ttl = notFoundCacheTTL
        case .error:
            ttl = errorCacheTTL
        case .synced, .plain, .instrumental:
            ttl = nil
        case .skipped:
            return now()
        }
        return ttl.map { now().addingTimeInterval($0) }
    }

    private func invalidateCache() {
        globalCacheGeneration &+= 1
        trackCacheGenerations.removeAll(keepingCapacity: true)
        cache.removeAll()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    private func invalidateCache(for identity: TrackIdentity) {
        trackCacheGenerations[identity, default: 0] &+= 1
        cache[identity] = nil
        inFlight.removeValue(forKey: identity)?.cancel()
    }

    private func cacheGeneration(for identity: TrackIdentity) -> CacheGeneration {
        CacheGeneration(
            global: globalCacheGeneration,
            track: trackCacheGenerations[identity] ?? 0
        )
    }

    private func nextCacheAccessOrdinal() -> UInt64 {
        cacheAccessOrdinal &+= 1
        return cacheAccessOrdinal
    }

    private func trimCacheIfNeeded() {
        guard cache.count > maximumCacheEntries else { return }
        let overflow = cache.count - maximumCacheEntries
        for identity in cache
            .sorted(by: { $0.value.accessOrdinal < $1.value.accessOrdinal })
            .prefix(overflow)
            .map(\.key)
        {
            cache.removeValue(forKey: identity)
        }
    }

    private static func captureSearch(
        _ operation: @escaping @Sendable () async throws -> [LyricsSearchHit]
    ) async -> SearchProviderResult {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func searchProviderName(_ provider: LyricsSourceKind) -> String {
        switch provider {
        case .lrclib: return "LRCLIB"
        case .netEase: return "NetEase"
        case .appleMusic: return "Apple Music"
        case .lyricsOvh: return "lyrics.ovh"
        }
    }

}
