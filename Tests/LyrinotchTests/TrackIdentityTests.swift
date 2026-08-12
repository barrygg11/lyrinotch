import Foundation
import XCTest
@testable import LyrinotchCore

final class TrackIdentityTests: XCTestCase {
    func testPlayerNamespacePreventsCrossCatalogIDCollision() {
        let track = makeTrack(id: "shared-id")

        let spotify = TrackIdentity(track: track, source: .spotify)
        let appleMusic = TrackIdentity(track: track, source: .appleMusic)

        XCTAssertNotEqual(spotify, appleMusic)
        XCTAssertNotEqual(spotify.storageKey, appleMusic.storageKey)
    }

    func testPersistentIDWinsOverChangingDisplayMetadataWithinOnePlayer() {
        let original = makeTrack(
            id: "catalog-id",
            name: "Song",
            artist: "Artist",
            album: "Original Album",
            duration: 200
        )
        let renamed = makeTrack(
            id: "catalog-id",
            name: "Song (Deluxe Edition)",
            artist: "Artist feat. Guest",
            album: "Deluxe Album",
            duration: 205
        )

        XCTAssertEqual(
            TrackIdentity(track: original, source: .spotify),
            TrackIdentity(track: renamed, source: .spotify)
        )
    }

    func testMetadataNormalizesPresentationButSeparatesLiveAndRemasteredVersions() {
        let original = makeTrack(
            id: nil,
            name: "  Song  ",
            artist: "Beyoncé",
            album: "Album",
            duration: 201.4
        )
        let presentationVariant = makeTrack(
            id: nil,
            name: "song",
            artist: "BEYONCE",
            album: " album ",
            duration: 202.4
        )
        let live = makeTrack(
            id: nil,
            name: "Song (Live)",
            artist: "Beyoncé",
            album: "Live at Home",
            duration: 241
        )
        let remaster = makeTrack(
            id: nil,
            name: "Song",
            artist: "Beyoncé",
            album: "Album (2026 Remaster)",
            duration: 201
        )

        let originalIdentity = TrackIdentity(track: original, source: .spotify)
        XCTAssertEqual(
            originalIdentity,
            TrackIdentity(track: presentationVariant, source: .spotify)
        )
        XCTAssertNotEqual(originalIdentity, TrackIdentity(track: live, source: .spotify))
        XCTAssertNotEqual(originalIdentity, TrackIdentity(track: remaster, source: .spotify))
    }

    func testReadySnapshotPropagatesPlayerNamespaceToTrack() {
        let snapshot = NowPlayingSnapshot(
            availability: .ready,
            track: makeTrack(id: "shared-id"),
            source: .appleMusic
        )

        XCTAssertEqual(snapshot.track.source, .appleMusic)
        XCTAssertEqual(
            snapshot.trackIdentity,
            TrackIdentity(track: snapshot.track, source: .appleMusic)
        )
    }

    func testVersionedStorageKeyRoundTripsEmptyAlbumMetadata() {
        let identity = TrackIdentity(
            track: makeTrack(
                id: nil,
                name: "Song",
                artist: "Artist",
                album: nil,
                duration: nil,
                source: .spotify
            )
        )

        XCTAssertEqual(TrackIdentity(storageKey: identity.storageKey), identity)
    }

    func testPinnedLyricsReadsAndMigratesLegacyIDKey() throws {
        let suite = "lyrinotch.identity.pinned.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let defaultsKey = "pinned"
        let track = makeTrack(id: "legacy-id", source: .spotify)
        let legacyKey = TrackIdentity.legacyStorageKey(for: track)
        let snapshot = LyricsSnapshot(
            availability: .synced,
            lines: [LyricLine(time: 1, text: "legacy")],
            source: "lrclib"
        )
        let legacy = LegacyPinnedEntry(snapshot: snapshot, updatedAt: Date(timeIntervalSince1970: 1))
        defaults.set(try JSONEncoder().encode([legacyKey: legacy]), forKey: defaultsKey)
        let store = PinnedLyricsStore(defaults: defaults, key: defaultsKey)

        XCTAssertEqual(store.snapshot(for: track), snapshot)

        let data = try XCTUnwrap(defaults.data(forKey: defaultsKey))
        let migrated = try JSONDecoder().decode([String: LegacyPinnedEntry].self, from: data)
        let modernKey = TrackIdentity(track: track).storageKey
        XCTAssertEqual(migrated[modernKey]?.snapshot, snapshot)
        XCTAssertNil(migrated[legacyKey])
    }

    func testOffsetStoreReadsAndMigratesLegacyMetadataKey() throws {
        let suite = "lyrinotch.identity.offset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let defaultsKey = "offsets"
        let track = makeTrack(
            id: nil,
            name: "Legacy Song",
            artist: "Legacy Artist",
            album: "Legacy Album",
            duration: 203,
            source: .appleMusic
        )
        let entry = TrackLyricOffsetEntry(offsetSeconds: 1.25, confidence: 0.8)
        let legacyKey = TrackIdentity.legacyStorageKey(for: track)
        defaults.set(try JSONEncoder().encode([legacyKey: entry]), forKey: defaultsKey)
        let store = TrackLyricOffsetStore(defaults: defaults, key: defaultsKey)
        let modernKey = TrackLyricOffsetStore.trackKey(for: track)

        XCTAssertEqual(store.offset(forTrackKey: modernKey), entry)

        let data = try XCTUnwrap(defaults.data(forKey: defaultsKey))
        let migrated = try JSONDecoder().decode([String: TrackLyricOffsetEntry].self, from: data)
        XCTAssertEqual(migrated[modernKey], entry)
        XCTAssertNil(migrated[legacyKey])
    }

    func testOffsetStoreKeepsSameIDSeparateAcrossPlayers() {
        let store = TrackLyricOffsetStore.ephemeral()
        let track = makeTrack(id: "shared-id")
        let spotifyEntry = TrackLyricOffsetEntry(offsetSeconds: 0.5, confidence: 0.8)
        let musicEntry = TrackLyricOffsetEntry(offsetSeconds: -0.75, confidence: 0.9)

        store.set(spotifyEntry, for: track, source: .spotify)
        store.set(musicEntry, for: track, source: .appleMusic)

        XCTAssertEqual(store.offset(for: track, source: .spotify), spotifyEntry)
        XCTAssertEqual(store.offset(for: track, source: .appleMusic), musicEntry)
    }

    func testOffsetStoreEvictsOldestEntryAtConfiguredBound() throws {
        let suite = "lyrinotch.identity.offset-bound.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TrackLyricOffsetStore(
            defaults: defaults,
            key: "offsets",
            maximumEntries: 2
        )
        let first = makeTrack(id: "first", source: .spotify)
        let second = makeTrack(id: "second", source: .spotify)
        let third = makeTrack(id: "third", source: .spotify)

        store.set(
            TrackLyricOffsetEntry(
                offsetSeconds: 0.1,
                confidence: 0.8,
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            for: first
        )
        store.set(
            TrackLyricOffsetEntry(
                offsetSeconds: 0.2,
                confidence: 0.8,
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            for: second
        )
        store.set(
            TrackLyricOffsetEntry(
                offsetSeconds: 0.3,
                confidence: 0.8,
                updatedAt: Date(timeIntervalSince1970: 3)
            ),
            for: third
        )

        XCTAssertNil(store.offset(for: first))
        XCTAssertNotNil(store.offset(for: second))
        XCTAssertNotNil(store.offset(for: third))
    }

    private func makeTrack(
        id: String?,
        name: String = "Song",
        artist: String = "Artist",
        album: String? = "Album",
        duration: TimeInterval? = 200,
        source: MusicPlayerSource? = nil
    ) -> Track {
        Track(
            id: id,
            name: name,
            artist: artist,
            album: album,
            duration: duration,
            position: 0,
            isPlaying: true,
            source: source
        )
    }
}

private struct LegacyPinnedEntry: Codable {
    var snapshot: LyricsSnapshot
    var updatedAt: Date
}
