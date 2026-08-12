import Foundation

/// Persists lyrics explicitly chosen from manual search, keyed by track identity.
public struct PinnedLyricsStore: @unchecked Sendable {
    public static let defaultKey = "app.lyrinotch.pinnedLyrics.v1"

    private struct Entry: Codable {
        var snapshot: LyricsSnapshot
        var updatedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let maximumEntries: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = PinnedLyricsStore.defaultKey,
        maximumEntries: Int = 100
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumEntries = max(1, maximumEntries)
    }

    public static func ephemeral() -> PinnedLyricsStore {
        let suite = "lyrinotch.pinned.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return PinnedLyricsStore(defaults: defaults, key: "pinned")
    }

    public func snapshot(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) -> LyricsSnapshot? {
        let identity = TrackIdentity(track: track, source: source)
        var map = all()
        if let current = map[identity.storageKey] {
            return current.snapshot
        }

        guard let legacyKey = legacyKey(for: identity, track: track, in: map),
              let legacy = map[legacyKey]
        else { return nil }

        // Move in one encoded dictionary write. Keeping the top-level defaults
        // key unchanged also means older app versions can still decode the map.
        map[identity.storageKey] = legacy
        map.removeValue(forKey: legacyKey)
        save(map)
        return legacy.snapshot
    }

    public func set(
        _ snapshot: LyricsSnapshot,
        for track: Track,
        source: MusicPlayerSource? = nil
    ) {
        let identity = TrackIdentity(track: track, source: source)
        var map = all()
        removeLegacyEntries(matching: identity, exactTrack: track, from: &map)
        map[identity.storageKey] = Entry(snapshot: snapshot, updatedAt: Date())
        if map.count > maximumEntries {
            let overflow = map.count - maximumEntries
            for item in map.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(overflow) {
                map.removeValue(forKey: item.key)
            }
        }
        save(map)
    }

    public func remove(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) {
        let identity = TrackIdentity(track: track, source: source)
        var map = all()
        map.removeValue(forKey: identity.storageKey)
        removeLegacyEntries(matching: identity, exactTrack: track, from: &map)
        save(map)
    }

    public func clearAll() {
        defaults.removeObject(forKey: key)
    }

    private func legacyKey(
        for identity: TrackIdentity,
        track: Track,
        in map: [String: Entry]
    ) -> String? {
        let exact = TrackIdentity.legacyStorageKey(for: track)
        if map[exact] != nil { return exact }
        return map.keys.sorted().first(where: identity.matchesLegacyStorageKey)
    }

    private func removeLegacyEntries(
        matching identity: TrackIdentity,
        exactTrack track: Track,
        from map: inout [String: Entry]
    ) {
        map.removeValue(forKey: TrackIdentity.legacyStorageKey(for: track))
        for legacyKey in map.keys.filter(identity.matchesLegacyStorageKey) {
            map.removeValue(forKey: legacyKey)
        }
    }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func save(_ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
