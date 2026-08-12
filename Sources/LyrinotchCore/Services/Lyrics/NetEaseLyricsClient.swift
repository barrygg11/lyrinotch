import Foundation

public enum NetEaseLyricsError: Error, LocalizedError, Sendable, Equatable {
    case httpStatus(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let status): return "NetEase HTTP \(status)"
        case .malformedResponse: return "NetEase returned an invalid response"
        }
    }
}

/// Unofficial NetEase Cloud Music search + lyric endpoints (best-effort, no API key).
/// Strong coverage for CJK TV themes / J-pop that LRCLIB often misses.
public struct NetEaseLyricsClient: LyricsFetching {
    private let session: URLSession
    private let userAgent: String
    private let maxAutomaticSearches: Int
    private let maxAutomaticLyricRequests: Int
    private let maximumResponseBytes: Int

    public init(
        session: URLSession = .shared,
        userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        maxAutomaticSearches: Int = 5,
        maxAutomaticLyricRequests: Int = 4,
        maximumResponseBytes: Int = LyricsInputLimits.maximumNetworkResponseBytes
    ) {
        self.session = session
        self.userAgent = userAgent
        self.maxAutomaticSearches = max(1, maxAutomaticSearches)
        self.maxAutomaticLyricRequests = max(1, maxAutomaticLyricRequests)
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    public func fetch(for track: Track) async throws -> LyricsSnapshot {
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTitle = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = TrackQueryNormalizer.primaryTitle(rawTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty, !title.isEmpty else {
            return LyricsSnapshot(availability: .skipped, source: "netease")
        }

        // NetEase indexes Simplified Chinese heavily — emit Hans variants too.
        let aHans = TrackQueryNormalizer.simplifiedChinese(artist)
        let tHans = TrackQueryNormalizer.simplifiedChinese(title)
        let aPrimary = TrackQueryNormalizer.primaryArtist(artist)
        let queries = uniqueNonEmpty([
            "\(artist) \(title)",
            "\(aHans) \(tHans)",
            "\(aPrimary) \(title)",
            "\(TrackQueryNormalizer.simplifiedChinese(aPrimary)) \(tHans)",
            title,
            tHans,
            "\(artist) \(rawTitle)",
            "\(aHans) \(TrackQueryNormalizer.simplifiedChinese(rawTitle))"
        ])

        var attemptedSongIDs = Set<Int>()
        var lyricRequestCount = 0
        var searchesWithoutNewCandidate = 0
        for q in queries.prefix(maxAutomaticSearches) {
            try Task.checkCancellation()
            let songs = try await rankedSongs(
                query: q,
                wantArtist: artist,
                wantTitle: title,
                duration: track.duration
            )
            var foundNewCandidate = false
            let newSongs = Array(
                songs.filter { !attemptedSongIDs.contains($0.id) }.prefix(2)
            )
            for song in newSongs {
                guard lyricRequestCount < maxAutomaticLyricRequests else { break }
                attemptedSongIDs.insert(song.id)
                foundNewCandidate = true
                lyricRequestCount += 1
                if let snap = try await lyricSnapshot(song: song) {
                    return snap
                }
            }
            if lyricRequestCount >= maxAutomaticLyricRequests { break }
            if foundNewCandidate {
                searchesWithoutNewCandidate = 0
            } else {
                searchesWithoutNewCandidate += 1
                if searchesWithoutNewCandidate >= 2 { break }
            }
        }
        return LyricsSnapshot(availability: .notFound, source: "netease", detail: "No match")
    }

    /// Search hits for the manual search UI.
    public func searchHits(query: String, limit: Int = 10) async throws -> [LyricsSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let safeLimit = min(50, max(1, limit))
        // Prefer Hans query form for NetEase.
        let qHans = TrackQueryNormalizer.simplifiedChinese(q)
        let songs = try await searchSongs(
            query: qHans.isEmpty ? q : qHans,
            limit: safeLimit
        )
        var hits: [LyricsSearchHit] = []
        for song in songs.prefix(safeLimit) {
            guard let snap = try await lyricSnapshot(song: song) else { continue }
            switch snap.availability {
            case .synced, .plain:
                break
            default:
                continue
            }
            hits.append(
                LyricsSearchHit(
                    id: "netease-\(song.id)",
                    trackName: song.name,
                    artistName: song.artist,
                    albumName: song.album,
                    duration: song.duration,
                    hasSynced: snap.availability == .synced,
                    sourceLabel: "NetEase",
                    snapshot: snap
                )
            )
        }
        return hits
    }

    // MARK: - Private

    private struct SongHit {
        var id: Int
        var name: String
        var artist: String
        var album: String?
        var duration: Double?
    }

    private func rankedSongs(
        query: String,
        wantArtist: String,
        wantTitle: String,
        duration: TimeInterval?
    ) async throws -> [SongHit] {
        let songs = try await searchSongs(query: query, limit: 10)
        guard !songs.isEmpty else { return [] }

        let ranked = songs.map { song -> (SongHit, Int) in
            let score = TrackQueryNormalizer.identityConfidence(
                wantArtist: wantArtist,
                wantTitle: wantTitle,
                gotArtist: song.artist,
                gotTitle: song.name,
                wantDuration: duration,
                gotDuration: song.duration
            )
            return (song, score)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }

        // Never return unranked search results — that caused random wrong lyrics.
        return ranked
            .filter { $0.1 >= TrackQueryNormalizer.minimumAcceptIdentity }
            .map(\.0)
    }

    private func searchSongs(query: String, limit: Int) async throws -> [SongHit] {
        // Prefer GET (more reliable from URLSession than empty POST).
        var components = URLComponents(string: "https://music.163.com/api/search/get/web")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "total", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let loaded = try await load(request)
        let data = loaded.data
        let status = loaded.response.statusCode
        if !(200..<300).contains(status) {
            // Fallback POST (some environments only accept this).
            return try await searchSongsPOST(query: query, limit: limit)
        }
        // A valid empty result is final; POST is only a protocol/parse fallback.
        if let songs = parseSongs(data) {
            return songs
        }
        return try await searchSongsPOST(query: query, limit: limit)
    }

    private func searchSongsPOST(query: String, limit: Int) async throws -> [SongHit] {
        var components = URLComponents(string: "https://music.163.com/api/search/get/web")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "total", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        let loaded = try await load(request)
        let data = loaded.data
        let status = loaded.response.statusCode
        guard (200..<300).contains(status) else {
            throw NetEaseLyricsError.httpStatus(status)
        }
        guard let songs = parseSongs(data) else {
            throw NetEaseLyricsError.malformedResponse
        }
        return songs
    }

    private func parseSongs(_ data: Data) -> [SongHit]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let songs = result["songs"] as? [[String: Any]]
        else { return nil }

        guard songs.count <= LyricsInputLimits.maximumNetworkRecords else { return nil }
        return songs.compactMap { song -> SongHit? in
            guard let id = intValue(song["id"]) else { return nil }
            let name = (song["name"] as? String) ?? ""
            let artists = (song["artists"] as? [[String: Any]]) ?? []
            let artist = artists.compactMap { $0["name"] as? String }.joined(separator: " / ")
            let album = (song["album"] as? [String: Any])?["name"] as? String
            let durationMs = doubleValue(song["duration"])
            let duration = durationMs
                .map { $0 > 1000 ? $0 / 1000.0 : $0 }
                .flatMap(LyricsInputLimits.validDuration)
            return SongHit(id: id, name: name, artist: artist, album: album, duration: duration)
        }
    }

    private func lyricSnapshot(song: SongHit) async throws -> LyricsSnapshot? {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(song.id)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 12

        let loaded = try await load(request)
        let data = loaded.data
        let status = loaded.response.statusCode
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw NetEaseLyricsError.httpStatus(status)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetEaseLyricsError.malformedResponse
        }

        // Encode matched identity so Composite can re-score (not the player track).
        let identityDetail = matchedIdentityDetail(song)
        let matchedTrack = LyricsMatchMetadata(
            title: song.name,
            artist: song.artist,
            duration: song.duration,
            providerID: String(song.id)
        )

        if let lrc = (json["lrc"] as? [String: Any])?["lyric"] as? String {
            let trimmed = lrc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                guard LyricsInputLimits.textFitsNetworkLimits(trimmed) else {
                    throw NetEaseLyricsError.malformedResponse
                }
                let lines = LRCParser.parse(
                    trimmed,
                    maximumLines: LyricsInputLimits.maximumNetworkTimedLines + 1
                )
                guard lines.count <= LyricsInputLimits.maximumNetworkTimedLines else {
                    throw NetEaseLyricsError.malformedResponse
                }
                if !lines.isEmpty {
                    return LyricsSnapshot(
                        availability: .synced,
                        lines: TrackQueryNormalizer.preferringJapaneseLines(lines),
                        source: "netease",
                        detail: identityDetail,
                        matchedTrack: matchedTrack
                    )
                }
                let plain = trimmed
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("[") }
                if !plain.isEmpty,
                   plain.count <= LyricsInputLimits.maximumNetworkSourceLines,
                   plain.allSatisfy({ $0.count <= LyricsInputLimits.maximumNetworkCharactersPerLine }) {
                    return LyricsSnapshot(
                        availability: .plain,
                        plainLines: TrackQueryNormalizer.preferringJapanesePlainLines(plain),
                        source: "netease",
                        detail: identityDetail,
                        matchedTrack: matchedTrack
                    )
                }
            }
        }

        if let nolyric = json["nolyric"] as? Bool, nolyric {
            return LyricsSnapshot(
                availability: .instrumental,
                source: "netease",
                detail: identityDetail,
                matchedTrack: matchedTrack
            )
        }
        return nil
    }

    /// `Artist — Title` form (same as lyrics.ovh) for composite identity scoring.
    private func matchedIdentityDetail(_ song: SongHit) -> String {
        let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = song.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty, !title.isEmpty {
            return "\(artist) — \(title)"
        }
        if !title.isEmpty { return title }
        return "id=\(song.id)"
    }

    private func load(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        do {
            return try await BoundedResponseLoader.data(
                for: request,
                in: session,
                maximumBytes: maximumResponseBytes
            )
        } catch is BoundedResponseError {
            throw NetEaseLyricsError.malformedResponse
        }
    }

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let i = any as? Int64 { return Int(i) }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private func uniqueNonEmpty(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }
}
