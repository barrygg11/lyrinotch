import Foundation

/// Minimal LRCLIB HTTP client. https://lrclib.net/docs
public protocol LyricsFetching: Sendable {
    func fetch(for track: Track) async throws -> LyricsSnapshot
}

public enum LRCLIBError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case decodingFailed
    case emptyTrack

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid LRCLIB URL"
        case .httpStatus(let code): return "LRCLIB HTTP \(code)"
        case .decodingFailed: return "Failed to decode LRCLIB response"
        case .emptyTrack: return "Track name/artist required"
        }
    }
}

struct LRCLIBRecord: Decodable, Sendable {
    var id: Int?
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?
}

public struct LRCLIBClient: LyricsFetching {
    public static let defaultUserAgent = "Lyrinotch/1.0 (macOS; personal; maintainer=barry)"

    /// Minimum score for a **search** hit to be accepted (exact `get` is trusted more).
    private static let minSearchAcceptScore = 150
    /// Free-text search needs a higher bar (easy to grab the wrong song).
    private static let minFreeTextAcceptScore = 200
    /// Prefer this much higher score before replacing an existing candidate.
    private static let replaceMargin = 15

    private let session: URLSession
    private let baseURL: URL
    private let userAgent: String
    private let maxAutomaticRequests: Int
    private let maximumResponseBytes: Int

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://lrclib.net/api")!,
        userAgent: String = LRCLIBClient.defaultUserAgent,
        maxAutomaticRequests: Int = 8,
        maximumResponseBytes: Int = LyricsInputLimits.maximumNetworkResponseBytes
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.maxAutomaticRequests = max(1, maxAutomaticRequests)
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    public func fetch(for track: Track) async throws -> LyricsSnapshot {
        let name = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !artist.isEmpty else {
            throw LRCLIBError.emptyTrack
        }
        let trackDuration = LyricsInputLimits.validDuration(track.duration)

        // Ranked candidates: higher score wins (not “more lyric lines”).
        var best: (snap: LyricsSnapshot, score: Int, fromExact: Bool)?
        var requestCount = 0

        func reserveRequest() -> Bool {
            guard requestCount < maxAutomaticRequests else { return false }
            requestCount += 1
            return true
        }

        func consider(record: LRCLIBRecord, score: Int, fromExact: Bool, freeTextMode: Bool) {
            let snap = snapshot(from: record)
            switch snap.availability {
            case .synced, .plain, .instrumental:
                break
            default:
                return
            }
            // Exact get is trusted: accept even with modest score.
            // Search / free-text must clear a higher bar to avoid random wrong songs.
            if !fromExact {
                let floor = freeTextMode ? Self.minFreeTextAcceptScore : Self.minSearchAcceptScore
                if score < floor { return }
                // Identity gate: refuse weak title/artist even if total score is high
                // (synced bonus alone used to let wrong free-text wins through).
                let identity = TrackQueryNormalizer.identityConfidence(
                    wantArtist: artist,
                    wantTitle: name,
                    gotArtist: record.artistName,
                    gotTitle: record.trackName,
                    wantDuration: trackDuration,
                    gotDuration: LyricsInputLimits.validDuration(record.duration)
                )
                if identity < TrackQueryNormalizer.minimumAcceptIdentity {
                    return
                }
            }
            if let current = best {
                // Prefer exact over search unless search is clearly better.
                if current.fromExact, !fromExact, score < current.score + 40 {
                    return
                }
                let rank: (LyricsAvailability) -> Int = {
                    switch $0 {
                    case .synced: return 3
                    case .plain: return 2
                    case .instrumental: return 1
                    default: return 0
                    }
                }
                let preferenceBonus = fromExact && !current.fromExact ? 30 : 0
                let improvesAvailabilityAtTie = score == current.score
                    && rank(snap.availability) > rank(current.snap.availability)
                if score + preferenceBonus < current.score + Self.replaceMargin,
                   !improvesAvailabilityAtTie
                {
                    return
                }
            }
            best = (snap, score, fromExact)
        }

        let queryJapanese =
            TrackQueryNormalizer.looksJapanese(name)
            || TrackQueryNormalizer.looksJapanese(artist)

        let pairs = TrackQueryNormalizer.artistTitleVariants(artist: artist, title: name)

        // 1) Exact `get` — spend at most five calls on the canonical metadata,
        // its no-duration fallback, album-qualified query, and two normalized variants.
        var exactQueries: [(artist: String, title: String, album: String?, duration: TimeInterval?)] = []
        if let primary = pairs.first {
            exactQueries.append(contentsOf: durationAttempts(trackDuration).prefix(2).map {
                (primary.0, primary.1, nil, $0)
            })
            if let album = track.album?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
                exactQueries.append((primary.0, primary.1, album, durationAttempts(trackDuration)[0]))
            }
        }
        for variant in pairs.dropFirst().prefix(2) {
            exactQueries.append((variant.0, variant.1, nil, durationAttempts(trackDuration)[0]))
        }

        for query in exactQueries {
            guard reserveRequest() else { break }
            if let record = try await getExact(
                artist: query.artist,
                title: query.title,
                album: query.album,
                duration: query.duration
            ) {
                let score = scoreRecord(
                    record,
                    duration: trackDuration,
                    wantArtist: artist,
                    wantTitle: name,
                    freeTextMode: false
                ) + (query.album == nil ? 80 : 100)
                consider(record: record, score: score, fromExact: true, freeTextMode: false)
                // For Japanese tracks, only early-return if the body is actually Japanese
                // (avoid locking onto English translation dumps from exact get).
                if let best, best.fromExact, best.snap.availability == .synced,
                   best.score >= (query.album == nil ? 200 : 220),
                   !queryJapanese || snapshotLooksJapanese(best.snap)
                {
                    return best.snap
                }
            }
        }

        // If exact already found solid synced lyrics, stop (avoid free-text wrong hits).
        // Still keep searching for Japanese tracks if current best is English-only.
        if let best, best.fromExact, best.snap.availability == .synced {
            if !queryJapanese || snapshotLooksJapanese(best.snap) {
                return best.snap
            }
        }

        // 2) Structured search: artist_name + track_name (still relatively safe).
        for (a, t) in pairs.prefix(3) {
            guard reserveRequest() else { break }
            if let ranked = try await searchBest(
                queryItems: [
                    URLQueryItem(name: "artist_name", value: a),
                    URLQueryItem(name: "track_name", value: t)
                ],
                duration: trackDuration,
                wantArtist: artist,
                wantTitle: name,
                freeTextMode: false
            ) {
                consider(record: ranked.record, score: ranked.score, fromExact: false, freeTextMode: false)
            }
        }

        if let best, best.snap.availability == .synced, best.score >= Self.minSearchAcceptScore + 40 {
            return best.snap
        }

        // 3) Free-text search last (riskiest — title-only can match wrong artists).
        for q in TrackQueryNormalizer.freeTextQueries(artist: artist, title: name) {
            guard reserveRequest() else { break }
            if let ranked = try await searchBest(
                queryItems: [URLQueryItem(name: "q", value: q)],
                duration: trackDuration,
                wantArtist: artist,
                wantTitle: name,
                freeTextMode: true
            ) {
                consider(record: ranked.record, score: ranked.score, fromExact: false, freeTextMode: true)
            }
        }

        if let best { return best.snap }
        return LyricsSnapshot(availability: .notFound, source: "lrclib", detail: "No match")
    }

    /// Manual search for the “search lyrics” UI.
    public func searchHits(query: String, limit: Int = 15) async throws -> [LyricsSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let safeLimit = min(LyricsInputLimits.maximumNetworkRecords, max(1, limit))
        let url = try makeURL(path: "search", query: [URLQueryItem(name: "q", value: q)])
        let (data, status) = try await data(from: url)
        if status == 404 { return [] }
        guard (200..<300).contains(status) else { throw LRCLIBError.httpStatus(status) }
        let records: [LRCLIBRecord]
        do {
            records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
        } catch {
            throw LRCLIBError.decodingFailed
        }
        guard records.count <= LyricsInputLimits.maximumNetworkRecords else {
            throw LRCLIBError.decodingFailed
        }
        let hits = records.compactMap { record -> LyricsSearchHit? in
            let snap = snapshot(from: record)
            switch snap.availability {
            case .synced, .plain, .instrumental:
                break
            default:
                return nil
            }
            let id = record.id.map { "lrclib-\($0)" }
                ?? "lrclib-\(record.artistName ?? "")-\(record.trackName ?? "")"
            return LyricsSearchHit(
                id: id,
                trackName: record.trackName ?? "?",
                artistName: record.artistName ?? "?",
                albumName: record.albumName,
                duration: LyricsInputLimits.validDuration(record.duration),
                hasSynced: snap.availability == .synced,
                sourceLabel: "LRCLIB",
                snapshot: snap
            )
        }
        return Array(hits.prefix(safeLimit))
    }

    private func snapshotLooksJapanese(_ snap: LyricsSnapshot) -> Bool {
        let timed = snap.lines.prefix(16).map(\.text).joined(separator: "\n")
        if TrackQueryNormalizer.looksJapanese(timed) { return true }
        let plain = snap.plainLines.prefix(16).joined(separator: "\n")
        if TrackQueryNormalizer.looksJapanese(plain) { return true }
        return false
    }

    // MARK: - Scoring

    /// Try with duration first (when known), then without — LRCLIB exact match is duration-sensitive.
    private func durationAttempts(_ duration: TimeInterval?) -> [TimeInterval?] {
        if let duration, duration > 0 {
            return [duration, nil]
        }
        return [nil]
    }

    private func scoreRecord(
        _ record: LRCLIBRecord,
        duration: TimeInterval?,
        wantArtist: String,
        wantTitle: String,
        freeTextMode: Bool
    ) -> Int {
        var score = 0
        let hasSynced = !(record.syncedLyrics ?? "").isEmpty
        let hasPlain = !(record.plainLyrics ?? "").isEmpty
        if hasSynced { score += 200 }
        else if hasPlain { score += 40 }
        if record.instrumental == true { score -= 60 }

        // Duration affinity
        if let duration = LyricsInputLimits.validDuration(duration),
           let rd = LyricsInputLimits.validDuration(record.duration),
           duration > 0 {
            let delta = abs(rd - duration)
            if delta < 2 { score += 70 }
            else if delta < 5 { score += 45 }
            else if delta < 12 { score += 20 }
            else if delta < 25 { score -= 10 }
            else { score -= min(80, Int(delta)) }
        }

        // Artist
        let artistMatched: Bool
        if let ra = record.artistName {
            artistMatched = TrackQueryNormalizer.artistsLooselyMatch(ra, wantArtist)
            if artistMatched { score += 60 }
            else if freeTextMode { score -= 160 } // free-text wrong-artist is the usual miss
            else { score -= 40 }
        } else {
            artistMatched = false
            if freeTextMode { score -= 80 }
        }

        // Title — stricter than bare `contains` on short strings
        let titleScore: Int
        if let rt = record.trackName {
            titleScore = TrackQueryNormalizer.titleMatchScore(want: wantTitle, candidate: rt)
            score += titleScore
            if freeTextMode, titleScore < 36 {
                score -= 80
            }
            if freeTextMode, titleScore < 30, !artistMatched {
                score -= 50
            }
        } else {
            titleScore = 0
            if freeTextMode { score -= 40 }
        }
        // Free-text with no artist identity is almost always a wrong song.
        if freeTextMode, !artistMatched {
            score -= 100
        }

        // Language / script affinity: Japanese tracks should keep Japanese lyrics,
        // not English translations that free-text search often ranks high.
        let queryJapanese =
            TrackQueryNormalizer.looksJapanese(wantTitle)
            || TrackQueryNormalizer.looksJapanese(wantArtist)
        if queryJapanese {
            let bodyJP = TrackQueryNormalizer.lyricBodyLooksJapanese(
                record.syncedLyrics,
                plain: record.plainLyrics
            )
            let bodyLatin = TrackQueryNormalizer.lyricBodyLooksMostlyLatin(
                record.syncedLyrics,
                plain: record.plainLyrics
            )
            if bodyJP {
                score += 90
            } else if bodyLatin {
                // Strong penalty so EN dumps lose to JP even with synced+duration.
                score -= 140
            }
        }

        return score
    }

    // MARK: - HTTP

    private func getExact(
        artist: String,
        title: String,
        album: String?,
        duration: TimeInterval?
    ) async throws -> LRCLIBRecord? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = LyricsInputLimits.validDuration(duration), duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }

        let url = try makeURL(path: "get", query: items)
        let (data, status) = try await data(from: url)

        if status == 404 {
            return nil
        }
        guard (200..<300).contains(status) else {
            throw LRCLIBError.httpStatus(status)
        }

        do {
            return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
        } catch {
            throw LRCLIBError.decodingFailed
        }
    }

    private func searchBest(
        queryItems: [URLQueryItem],
        duration: TimeInterval?,
        wantArtist: String,
        wantTitle: String,
        freeTextMode: Bool
    ) async throws -> (record: LRCLIBRecord, score: Int)? {
        let url = try makeURL(path: "search", query: queryItems)
        let (data, status) = try await data(from: url)

        if status == 404 {
            return nil
        }
        guard (200..<300).contains(status) else {
            throw LRCLIBError.httpStatus(status)
        }

        let records: [LRCLIBRecord]
        do {
            records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
        } catch {
            throw LRCLIBError.decodingFailed
        }

        guard !records.isEmpty else { return nil }
        guard records.count <= LyricsInputLimits.maximumNetworkRecords else {
            return nil
        }

        let scored = records.map { record -> (LRCLIBRecord, Int) in
            (
                record,
                scoreRecord(
                    record,
                    duration: duration,
                    wantArtist: wantArtist,
                    wantTitle: wantTitle,
                    freeTextMode: freeTextMode
                )
            )
        }
        .sorted { $0.1 > $1.1 }

        let floor = freeTextMode ? Self.minFreeTextAcceptScore : Self.minSearchAcceptScore
        guard let top = scored.first, top.1 >= floor else {
            return nil
        }
        // Extra identity gate on the top search hit.
        let identity = TrackQueryNormalizer.identityConfidence(
            wantArtist: wantArtist,
            wantTitle: wantTitle,
            gotArtist: top.0.artistName,
            gotTitle: top.0.trackName,
            wantDuration: duration,
            gotDuration: LyricsInputLimits.validDuration(top.0.duration)
        )
        guard identity >= TrackQueryNormalizer.minimumAcceptIdentity else {
            return nil
        }
        return (top.0, top.1)
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw LRCLIBError.invalidURL
        }
        components.queryItems = query
        guard let url = components.url else {
            throw LRCLIBError.invalidURL
        }
        return url
    }

    private func data(from url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        do {
            let loaded = try await BoundedResponseLoader.data(
                for: request,
                in: session,
                maximumBytes: maximumResponseBytes
            )
            return (loaded.data, loaded.response.statusCode)
        } catch is BoundedResponseError {
            throw LRCLIBError.decodingFailed
        }
    }

    private func snapshot(from record: LRCLIBRecord) -> LyricsSnapshot {
        let matchedTrack = LyricsMatchMetadata(
            title: record.trackName ?? "",
            artist: record.artistName ?? "",
            duration: LyricsInputLimits.validDuration(record.duration),
            providerID: record.id.map(String.init)
        )
        if record.instrumental == true {
            return LyricsSnapshot(
                availability: .instrumental,
                source: "lrclib",
                detail: record.id.map { "id=\($0)" },
                matchedTrack: matchedTrack
            )
        }

        if let synced = record.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !synced.isEmpty {
            guard LyricsInputLimits.textFitsNetworkLimits(synced) else {
                return LyricsSnapshot(availability: .notFound, source: "lrclib")
            }
            let parsed = LRCParser.parse(
                synced,
                maximumLines: LyricsInputLimits.maximumNetworkTimedLines + 1
            )
            guard parsed.count <= LyricsInputLimits.maximumNetworkTimedLines else {
                return LyricsSnapshot(availability: .notFound, source: "lrclib")
            }
            // Strip romaji companion lines from bilingual JP LRC files.
            let lines = TrackQueryNormalizer.preferringJapaneseLines(parsed)
            if !lines.isEmpty {
                return LyricsSnapshot(
                    availability: .synced,
                    lines: lines,
                    source: "lrclib",
                    detail: record.id.map { "id=\($0)" },
                    matchedTrack: matchedTrack
                )
            }
        }

        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty,
           LyricsInputLimits.textFitsNetworkLimits(plain) {
            let plainLines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let preferred = TrackQueryNormalizer.preferringJapanesePlainLines(plainLines)
            return LyricsSnapshot(
                availability: .plain,
                plainLines: preferred,
                source: "lrclib",
                detail: record.id.map { "id=\($0)" },
                matchedTrack: matchedTrack
            )
        }

        return LyricsSnapshot(
            availability: .notFound,
            source: "lrclib",
            detail: "Record had no lyrics",
            matchedTrack: matchedTrack
        )
    }
}
