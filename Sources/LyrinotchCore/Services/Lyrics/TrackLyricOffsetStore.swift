import Foundation

/// One auto-calibrated (or user-pinned) offset for a track.
public struct TrackLyricOffsetEntry: Codable, Equatable, Sendable {
    public var offsetSeconds: Double
    public var confidence: Double
    public var updatedAt: Date
    /// `auto` from mic alignment, `manual` from nudging, or `tap` from line-start alignment.
    public var source: String
    /// Stable identity of the exact lyric timeline this correction was measured against.
    /// Legacy entries decode as `nil` and must be revalidated before use.
    public var lyricsFingerprint: String?
    /// Output route used by microphone calibration. Automatic corrections include
    /// route latency and must not silently transfer from speakers to another route.
    public var audioRoute: String?

    public init(
        offsetSeconds: Double,
        confidence: Double,
        updatedAt: Date = Date(),
        source: String = "auto",
        lyricsFingerprint: String? = nil,
        audioRoute: String? = nil
    ) {
        self.offsetSeconds = min(6, max(-6, offsetSeconds))
        self.confidence = min(1, max(0, confidence))
        self.updatedAt = updatedAt
        self.source = source
        self.lyricsFingerprint = lyricsFingerprint
        self.audioRoute = audioRoute
    }
}

/// Persists per-track lyric timeline offsets.
public struct TrackLyricOffsetStore {
    public static let defaultKey = "app.lyrinotch.trackLyricOffsets.v1"

    private let defaults: UserDefaults
    private let key: String
    private let maximumEntries: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = TrackLyricOffsetStore.defaultKey,
        maximumEntries: Int = 500
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumEntries = max(1, maximumEntries)
    }

    public static func ephemeral() -> TrackLyricOffsetStore {
        let suite = "lyrinotch.offsets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return TrackLyricOffsetStore(defaults: defaults, key: "offsets")
    }

    public func offset(forTrackKey trackKey: String) -> TrackLyricOffsetEntry? {
        var map = all()
        if let current = map[trackKey] { return current }
        guard let identity = TrackIdentity(storageKey: trackKey),
              let legacyKey = map.keys.sorted().first(where: identity.matchesLegacyStorageKey),
              let legacy = map[legacyKey]
        else { return nil }

        map[trackKey] = legacy
        map.removeValue(forKey: legacyKey)
        save(map)
        return legacy
    }

    public func set(_ entry: TrackLyricOffsetEntry, forTrackKey trackKey: String) {
        var map = all()
        if let identity = TrackIdentity(storageKey: trackKey) {
            for legacyKey in map.keys.filter(identity.matchesLegacyStorageKey) {
                map.removeValue(forKey: legacyKey)
            }
        }
        map[trackKey] = entry
        if map.count > maximumEntries {
            let overflow = map.count - maximumEntries
            for key in map
                .sorted(by: { $0.value.updatedAt < $1.value.updatedAt })
                .prefix(overflow)
                .map(\.key)
            {
                map.removeValue(forKey: key)
            }
        }
        save(map)
    }

    public func remove(forTrackKey trackKey: String) {
        var map = all()
        map.removeValue(forKey: trackKey)
        if let identity = TrackIdentity(storageKey: trackKey) {
            for legacyKey in map.keys.filter(identity.matchesLegacyStorageKey) {
                map.removeValue(forKey: legacyKey)
            }
        }
        save(map)
    }

    public func offset(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) -> TrackLyricOffsetEntry? {
        offset(forTrackKey: TrackIdentity(track: track, source: source).storageKey)
    }

    public func set(
        _ entry: TrackLyricOffsetEntry,
        for track: Track,
        source: MusicPlayerSource? = nil
    ) {
        set(entry, forTrackKey: TrackIdentity(track: track, source: source).storageKey)
    }

    public func remove(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) {
        remove(forTrackKey: TrackIdentity(track: track, source: source).storageKey)
    }

    public func clearAll() {
        defaults.removeObject(forKey: key)
    }

    /// Stable key shared with lyrics cache identity.
    public static func trackKey(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) -> String {
        TrackIdentity(track: track, source: source).storageKey
    }

    // MARK: - Private

    private func all() -> [String: TrackLyricOffsetEntry] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: TrackLyricOffsetEntry].self, from: data)) ?? [:]
    }

    private func save(_ map: [String: TrackLyricOffsetEntry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
