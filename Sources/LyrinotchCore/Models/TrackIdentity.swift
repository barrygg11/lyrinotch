import Foundation

/// Stable, player-namespaced identity shared by playback, lyrics, artwork, and
/// per-track persistence.
///
/// Player IDs are only unique inside their originating catalog. When an ID is
/// unavailable, normalized metadata deliberately keeps album and a coarse
/// duration bucket so studio, live, and remastered versions do not share state.
public struct TrackIdentity: Hashable, Sendable {
    public enum Basis: Hashable, Sendable {
        case persistentID(String)
        case metadata(artist: String, name: String, album: String, durationBucket: Int?)
    }

    public let source: MusicPlayerSource?
    public let basis: Basis

    public init(track: Track, source: MusicPlayerSource? = nil) {
        // The source captured with the player sample is authoritative; the
        // parameter is a compatibility fallback for standalone Track callers.
        self.source = track.source ?? source
        let trimmedID = track.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedID.isEmpty {
            basis = .persistentID(trimmedID)
        } else {
            basis = .metadata(
                artist: Self.normalize(track.artist),
                name: Self.normalize(track.name),
                album: Self.normalize(track.album ?? ""),
                durationBucket: Self.durationBucket(track.duration)
            )
        }
    }

    /// Versioned key suitable for UserDefaults dictionaries and memory caches.
    public var storageKey: String {
        let namespace = source?.rawValue ?? "unknown"
        switch basis {
        case .persistentID(let id):
            return "track:v2:\(namespace):id:\(Self.encode(id))"
        case .metadata(let artist, let name, let album, let durationBucket):
            return [
                "track", "v2", namespace, "meta",
                Self.encode(artist), Self.encode(name), Self.encode(album),
                durationBucket.map(String.init) ?? "-"
            ].joined(separator: ":")
        }
    }

    /// Decodes a v2 key so stores that still expose their historical String API
    /// can migrate old entries without requiring every caller to change at once.
    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, parts[0] == "track", parts[1] == "v2" else { return nil }

        if parts[2] == "unknown" {
            source = nil
        } else if let decodedSource = MusicPlayerSource(rawValue: parts[2]) {
            source = decodedSource
        } else {
            return nil
        }

        switch parts[3] {
        case "id":
            guard parts.count == 5, let id = Self.decode(parts[4]), !id.isEmpty else { return nil }
            basis = .persistentID(id)
        case "meta":
            guard parts.count == 8,
                  let artist = Self.decode(parts[4]),
                  let name = Self.decode(parts[5]),
                  let album = Self.decode(parts[6])
            else { return nil }
            let bucket: Int?
            if parts[7] == "-" {
                bucket = nil
            } else if let value = Int(parts[7]) {
                bucket = value
            } else {
                return nil
            }
            basis = .metadata(
                artist: artist,
                name: name,
                album: album,
                durationBucket: bucket
            )
        default:
            return nil
        }
    }

    /// Matches the unnamespaced v1 key used before TrackIdentity existed.
    /// Album was absent from that format, so a legacy value is claimed by the
    /// first concrete v2 identity that reads it and then removed atomically.
    func matchesLegacyStorageKey(_ key: String) -> Bool {
        switch basis {
        case .persistentID(let id):
            guard key.hasPrefix("id:") else { return false }
            return key.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines) == id

        case .metadata(let artist, let name, _, let durationBucket):
            guard key.hasPrefix("meta:") else { return false }
            let payload = String(key.dropFirst(5))
            guard let firstSeparator = payload.firstIndex(of: "|"),
                  let lastSeparator = payload.lastIndex(of: "|"),
                  firstSeparator < lastSeparator
            else { return false }

            let legacyArtist = String(payload[..<firstSeparator])
            let legacyNameStart = payload.index(after: firstSeparator)
            let legacyName = String(payload[legacyNameStart..<lastSeparator])
            let legacyDuration = String(payload[payload.index(after: lastSeparator)...])
            let parsedDurationBucket: Int?
            if legacyDuration == "-" {
                parsedDurationBucket = nil
            } else if let seconds = Int(legacyDuration) {
                parsedDurationBucket = Self.durationBucket(TimeInterval(seconds))
            } else {
                return false
            }

            return Self.normalize(legacyArtist) == artist
                && Self.normalize(legacyName) == name
                && parsedDurationBucket == durationBucket
        }
    }

    /// Exact v1 key generation retained solely for safe persisted-data migration.
    static func legacyStorageKey(for track: Track) -> String {
        if let id = track.id, !id.isEmpty {
            return "id:\(id)"
        }
        let duration: String
        if let value = LyricsInputLimits.validDuration(track.duration) {
            duration = String(Int(value.rounded()))
        } else {
            duration = "-"
        }
        return "meta:\(track.artist.lowercased())|\(track.name.lowercased())|\(duration)"
    }

    private static func normalize(_ value: String) -> String {
        let collapsedWhitespace = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsedWhitespace
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func durationBucket(_ duration: TimeInterval?) -> Int? {
        guard let duration = LyricsInputLimits.validDuration(duration) else { return nil }
        let bucketSize: TimeInterval = 5
        return Int((duration / bucketSize).rounded()) * Int(bucketSize)
    }

    private static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func decode(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
