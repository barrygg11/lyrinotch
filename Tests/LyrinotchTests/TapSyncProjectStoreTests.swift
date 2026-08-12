import Foundation
import XCTest
@testable import LyrinotchCore

final class TapSyncProjectStoreTests: XCTestCase {
    func testProjectAndUndoHistorySurviveStoreRecreation() throws {
        try withStore { defaults, key, store in
            let track = makeTrack(id: "persist")
            var project = try store.prepare(for: track, lyrics: lyrics("one", "two", "three"))
            try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 5)
            try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 45)
            try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 48)
            store.set(project)

            let reopened = TapSyncProjectStore(defaults: defaults, key: key)
            var loaded = try XCTUnwrap(reopened.latest(for: track))
            XCTAssertEqual(loaded.anchors[1].playbackTime, 48)
            XCTAssertTrue(loaded.undoLastEdit())
            XCTAssertEqual(loaded.anchors[1].playbackTime, 45)
        }
    }

    func testMatchingRejectsFingerprintMismatchAndAcceptsPinnedGeneratedOutput() throws {
        try withStore { _, _, store in
            let track = makeTrack(id: "fingerprint")
            let original = lyrics(["one", "two", "three"], source: "provider-a")
            var project = try store.prepare(for: track, lyrics: original)
            try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 4)
            try project.recordOrReplaceAnchor(lineIndex: 2, playbackTime: 44)
            store.set(project)

            XCTAssertNil(
                store.project(
                    for: track,
                    matching: lyrics(["one", "changed", "three"], source: "provider-a")
                )
            )
            XCTAssertNil(
                store.project(
                    for: track,
                    matching: lyrics(["one", "two", "three"], source: "provider-b")
                )
            )
            XCTAssertEqual(store.project(for: track, matching: original), project)

            let pinnedOutput = try project.syncedSnapshot()
            XCTAssertEqual(store.project(for: track, matching: pinnedOutput), project)
        }
    }

    func testPlainProjectSurvivesSmallOrMissingPlaybackDurationRefresh() throws {
        try withStore { _, _, store in
            let originalTrack = makeTrack(id: "duration-refresh")
            let originalLyrics = lyrics("one", "two", "three")
            var project = try store.prepare(for: originalTrack, lyrics: originalLyrics)
            try project.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 5)
            store.set(project)

            var driftedTrack = originalTrack
            driftedTrack.duration = 120.04
            var temporarilyMissingDuration = originalTrack
            temporarilyMissingDuration.duration = nil

            XCTAssertEqual(
                store.project(for: driftedTrack, matching: originalLyrics)?.anchors,
                project.anchors
            )
            XCTAssertEqual(
                store.project(for: temporarilyMissingDuration, matching: originalLyrics)?.anchors,
                project.anchors
            )
        }
    }

    func testPreparingNewFingerprintInvalidatesOldProjectForSameTrack() throws {
        try withStore { _, _, store in
            let track = makeTrack(id: "replacement")
            let oldProject = try store.prepare(
                for: track,
                lyrics: lyrics(["old one", "old two"], source: "old")
            )
            let replacement = try store.prepare(
                for: track,
                lyrics: lyrics(["new one", "new two"], source: "new")
            )

            XCTAssertNil(
                store.project(
                    for: track,
                    lyricsFingerprint: oldProject.baseLyricsFingerprint
                )
            )
            XCTAssertEqual(store.latest(for: track), replacement)
        }
    }

    func testSamePersistentIDRemainsSeparateAcrossPlayerSources() throws {
        try withStore { _, _, store in
            let unnamespaced = makeTrack(id: "shared", source: nil)
            var spotify = try store.prepare(
                for: unnamespaced,
                source: .spotify,
                lyrics: lyrics("spotify one", "spotify two")
            )
            try spotify.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 5)
            store.set(spotify)

            var music = try store.prepare(
                for: unnamespaced,
                source: .appleMusic,
                lyrics: lyrics("music one", "music two")
            )
            try music.recordOrReplaceAnchor(lineIndex: 0, playbackTime: 9)
            store.set(music)

            XCTAssertEqual(
                store.latest(for: unnamespaced, source: .spotify)?.anchors.first?.playbackTime,
                5
            )
            XCTAssertEqual(
                store.latest(for: unnamespaced, source: .appleMusic)?.anchors.first?.playbackTime,
                9
            )
        }
    }

    func testLegacyTrackKeyMigratesOnRead() throws {
        try withStore { defaults, key, store in
            let track = makeTrack(id: "legacy", source: .spotify)
            let project = try TapSyncProject(track: track, lyrics: lyrics("one", "two"))
            let legacyKey = TrackIdentity.legacyStorageKey(for: track)
            defaults.set(
                try JSONEncoder().encode([legacyKey: project]),
                forKey: key
            )

            XCTAssertEqual(store.latest(for: track), project)

            let data = try XCTUnwrap(defaults.data(forKey: key))
            let persisted = try JSONDecoder().decode([String: TapSyncProject].self, from: data)
            XCTAssertNil(persisted[legacyKey])
            XCTAssertNotNil(persisted[TrackIdentity(track: track).storageKey])
        }
    }

    func testMaximumEntryBoundEvictsOldestProject() throws {
        try withStore(maximumEntries: 2) { _, _, store in
            let first = makeTrack(id: "first")
            let second = makeTrack(id: "second")
            let third = makeTrack(id: "third")
            try store.prepare(
                for: first,
                lyrics: lyrics("one"),
                updatedAt: Date(timeIntervalSince1970: 1)
            )
            try store.prepare(
                for: second,
                lyrics: lyrics("two"),
                updatedAt: Date(timeIntervalSince1970: 2)
            )
            try store.prepare(
                for: third,
                lyrics: lyrics("three"),
                updatedAt: Date(timeIntervalSince1970: 3)
            )

            XCTAssertNil(store.latest(for: first))
            XCTAssertNotNil(store.latest(for: second))
            XCTAssertNotNil(store.latest(for: third))
        }
    }

    func testRemoveAndClearAll() throws {
        try withStore { _, _, store in
            let first = makeTrack(id: "first")
            let second = makeTrack(id: "second")
            try store.prepare(for: first, lyrics: lyrics("one"))
            try store.prepare(for: second, lyrics: lyrics("two"))

            store.remove(for: first)
            XCTAssertNil(store.latest(for: first))
            XCTAssertNotNil(store.latest(for: second))

            store.clearAll()
            XCTAssertNil(store.latest(for: second))
        }
    }

    func testUnsupportedSchemaFailsClosedWithoutCrashing() throws {
        try withStore { defaults, key, store in
            let track = makeTrack(id: "corrupt")
            let project = try TapSyncProject(track: track, lyrics: lyrics("one"))
            let encoded = try JSONEncoder().encode([project.trackKey: project])
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: [String: Any]]
            )
            var encodedProject = try XCTUnwrap(object[project.trackKey])
            encodedProject["schemaVersion"] = 999
            object[project.trackKey] = encodedProject
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)

            XCTAssertNil(store.latest(for: track))
        }
    }

    func testCorruptEntryDoesNotHideOrEraseOtherProjects() throws {
        try withStore { defaults, key, store in
            let validTrack = makeTrack(id: "valid")
            let corruptTrack = makeTrack(id: "corrupt")
            let valid = try TapSyncProject(track: validTrack, lyrics: lyrics("valid line"))
            let corrupt = try TapSyncProject(track: corruptTrack, lyrics: lyrics("bad line"))
            let encoded = try JSONEncoder().encode([
                valid.trackKey: valid,
                corrupt.trackKey: corrupt
            ])
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoded) as? [String: [String: Any]]
            )
            var corruptObject = try XCTUnwrap(object[corrupt.trackKey])
            corruptObject["schemaVersion"] = 999
            object[corrupt.trackKey] = corruptObject
            defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)

            XCTAssertEqual(store.latest(for: validTrack), valid)
            XCTAssertNil(store.latest(for: corruptTrack))

            let newTrack = makeTrack(id: "new")
            try store.prepare(for: newTrack, lyrics: lyrics("new line"))
            XCTAssertEqual(store.latest(for: validTrack), valid)
            XCTAssertNotNil(store.latest(for: newTrack))
        }
    }

    private func withStore(
        maximumEntries: Int = 100,
        _ body: (UserDefaults, String, TapSyncProjectStore) throws -> Void
    ) throws {
        let suite = "lyrinotch.tap-sync.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "tap-projects"
        let store = TapSyncProjectStore(
            defaults: defaults,
            key: key,
            maximumEntries: maximumEntries
        )
        try body(defaults, key, store)
    }

    private func lyrics(_ lines: String...) -> LyricsSnapshot {
        lyrics(lines, source: "plain-provider")
    }

    private func lyrics(_ lines: [String], source: String) -> LyricsSnapshot {
        LyricsSnapshot(availability: .plain, plainLines: lines, source: source)
    }

    private func makeTrack(
        id: String,
        source: MusicPlayerSource? = .spotify
    ) -> Track {
        Track(
            id: id,
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: 120,
            position: 0,
            isPlaying: true,
            source: source
        )
    }
}
