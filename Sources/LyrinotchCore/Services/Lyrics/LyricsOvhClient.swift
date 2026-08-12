import Foundation

public enum LyricsOvhError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case httpStatus(Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid lyrics.ovh URL"
        case .httpStatus(let status): return "lyrics.ovh HTTP \(status)"
        case .malformedResponse: return "lyrics.ovh returned an invalid response"
        }
    }
}

/// Plain-text lyrics from the free lyrics.ovh API.
/// Docs: `GET https://api.lyrics.ovh/v1/{artist}/{title}`
public struct LyricsOvhClient: LyricsFetching {
    private let session: URLSession
    private let userAgent: String
    private let baseURL: URL
    private let maximumResponseBytes: Int

    public init(
        session: URLSession = .shared,
        userAgent: String = "Lyrinotch/1.0 (macOS; personal)",
        baseURL: URL = URL(string: "https://api.lyrics.ovh/v1")!,
        maximumResponseBytes: Int = LyricsInputLimits.maximumNetworkResponseBytes
    ) {
        self.session = session
        self.userAgent = userAgent
        self.baseURL = baseURL
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    public func fetch(for track: Track) async throws -> LyricsSnapshot {
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = TrackQueryNormalizer.primaryTitle(track.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty, !title.isEmpty else {
            return LyricsSnapshot(availability: .skipped, source: "lyrics.ovh")
        }

        // Try a few title/artist cleanups.
        let artists = [artist, TrackQueryNormalizer.primaryArtist(artist)]
        let titles = [title, track.name.trimmingCharacters(in: .whitespacesAndNewlines)]
        var tried = Set<String>()

        for a in artists {
            for t in titles {
                let key = "\(a.lowercased())|\(t.lowercased())"
                guard tried.insert(key).inserted else { continue }
                if let snap = try await fetchOnce(artist: a, title: t) {
                    return snap
                }
            }
        }
        return LyricsSnapshot(
            availability: .notFound,
            source: "lyrics.ovh",
            detail: "No match"
        )
    }

    private func fetchOnce(artist: String, title: String) async throws -> LyricsSnapshot? {
        // `/`, `?`, and `#` belong to the artist/title, not the URL structure.
        let forbidden = CharacterSet(charactersIn: "/?#%")
        let allowed = CharacterSet.urlPathAllowed.subtracting(forbidden)
        guard let aEnc = artist.addingPercentEncoding(withAllowedCharacters: allowed),
              let tEnc = title.addingPercentEncoding(withAllowedCharacters: allowed)
        else {
            throw LyricsOvhError.invalidURL
        }
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/\(aEnc)/\(tEnc)") else {
            throw LyricsOvhError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let loaded: (data: Data, response: HTTPURLResponse)
        do {
            loaded = try await BoundedResponseLoader.data(
                for: request,
                in: session,
                maximumBytes: maximumResponseBytes
            )
        } catch is BoundedResponseError {
            throw LyricsOvhError.malformedResponse
        }
        let data = loaded.data
        let status = loaded.response.statusCode
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw LyricsOvhError.httpStatus(status)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let lyrics = json["lyrics"] as? String
        else { throw LyricsOvhError.malformedResponse }

        let text = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard LyricsInputLimits.textFitsNetworkLimits(text) else {
            throw LyricsOvhError.malformedResponse
        }

        let plainLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Paroles de la chanson") }

        guard !plainLines.isEmpty else { return nil }
        return LyricsSnapshot(
            availability: .plain,
            plainLines: TrackQueryNormalizer.preferringJapanesePlainLines(plainLines),
            source: "lyrics.ovh",
            detail: "\(artist) — \(title)",
            matchedTrack: LyricsMatchMetadata(title: title, artist: artist)
        )
    }
}
