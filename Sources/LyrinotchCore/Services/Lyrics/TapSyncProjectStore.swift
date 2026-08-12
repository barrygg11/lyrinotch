import Foundation

/// Bounded persistence for tap-sync projects, namespaced by `TrackIdentity`.
public struct TapSyncProjectStore: @unchecked Sendable {
    public static let defaultKey = "app.lyrinotch.tapSyncProjects.v1"

    private let defaults: UserDefaults
    private let key: String
    private let maximumEntries: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = TapSyncProjectStore.defaultKey,
        maximumEntries: Int = 100
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumEntries = max(1, maximumEntries)
    }

    public static func ephemeral() -> TapSyncProjectStore {
        let suite = "lyrinotch.tap-sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return TapSyncProjectStore(defaults: defaults, key: "tap-sync")
    }

    /// Creates and immediately persists a replacement project for this track.
    @discardableResult
    public func prepare(
        for track: Track,
        source: MusicPlayerSource? = nil,
        lyrics: LyricsSnapshot,
        updatedAt: Date = Date()
    ) throws -> TapSyncProject {
        let project = try TapSyncProject(
            track: track,
            source: source,
            lyrics: lyrics,
            updatedAt: updatedAt
        )
        set(project)
        return project
    }

    /// Latest project for a track. Intended for explicit “resume editing”.
    /// Use the matching overload before applying a project automatically.
    public func latest(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) -> TapSyncProject? {
        latest(forTrackKey: TrackIdentity(track: track, source: source).storageKey)
    }

    public func latest(forTrackKey trackKey: String) -> TapSyncProject? {
        var map = all()
        if let current = map[trackKey] {
            guard current.trackKey == trackKey else {
                map.removeValue(forKey: trackKey)
                save(map)
                return nil
            }
            return current
        }

        guard let identity = TrackIdentity(storageKey: trackKey),
              let legacyKey = map.keys.sorted().first(where: identity.matchesLegacyStorageKey),
              var legacy = map[legacyKey]
        else { return nil }

        // Claim a pre-TrackIdentity key atomically, mirroring the other
        // per-track stores. The project also carries the key for readback checks.
        legacy.migrateTrackKey(to: trackKey)
        map[trackKey] = legacy
        map.removeValue(forKey: legacyKey)
        save(map)
        return legacy
    }

    /// Returns a project only when the current lyrics are its original input or
    /// generated/pinned output from the same base lyrics (including a stale
    /// revision saved before the latest edit). A provider/fingerprint change
    /// cannot silently inherit old anchors.
    public func project(
        for track: Track,
        source: MusicPlayerSource? = nil,
        matching lyrics: LyricsSnapshot
    ) -> TapSyncProject? {
        guard let project = latest(for: track, source: source),
              project.matches(lyrics: lyrics, duration: track.duration)
        else { return nil }
        return project
    }

    public func project(
        for track: Track,
        source: MusicPlayerSource? = nil,
        lyricsFingerprint: String
    ) -> TapSyncProject? {
        guard let project = latest(for: track, source: source),
              project.baseLyricsFingerprint == lyricsFingerprint
        else { return nil }
        return project
    }

    /// Persists the full editing state, including replace-aware undo history.
    /// A new base fingerprint replaces (invalidates) the old project for the
    /// same concrete track, but never affects another player namespace.
    public func set(_ project: TapSyncProject) {
        var map = all()
        if let identity = TrackIdentity(storageKey: project.trackKey) {
            for legacyKey in map.keys.filter(identity.matchesLegacyStorageKey) {
                map.removeValue(forKey: legacyKey)
            }
        }
        map[project.trackKey] = project
        if map.count > maximumEntries {
            let overflow = map.count - maximumEntries
            for oldKey in map
                .sorted(by: { $0.value.updatedAt < $1.value.updatedAt })
                .prefix(overflow)
                .map(\.key)
            {
                map.removeValue(forKey: oldKey)
            }
        }
        save(map)
    }

    public func remove(
        for track: Track,
        source: MusicPlayerSource? = nil
    ) {
        remove(forTrackKey: TrackIdentity(track: track, source: source).storageKey)
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

    public func clearAll() {
        defaults.removeObject(forKey: key)
    }

    private func all() -> [String: TapSyncProject] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        // Decode entries independently. One truncated or future-schema project
        // must not hide every other valid track or cause them to be discarded by
        // the next successful write.
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        let decoder = JSONDecoder()
        var projects: [String: TapSyncProject] = [:]
        projects.reserveCapacity(dictionary.count)
        for (trackKey, rawProject) in dictionary {
            guard JSONSerialization.isValidJSONObject(rawProject),
                  let projectData = try? JSONSerialization.data(withJSONObject: rawProject),
                  let project = try? decoder.decode(TapSyncProject.self, from: projectData)
            else { continue }
            projects[trackKey] = project
        }
        return projects
    }

    private func save(_ map: [String: TapSyncProject]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
