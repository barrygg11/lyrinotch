import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class AppModelRegressionTests: XCTestCase {
    @MainActor
    func testTrackChangeDuringArtworkLoadStopsStaleLyricsSideEffects() async {
        let artworkGate = SuspensionGate()
        let oldTrack = makeTrack(id: "old", name: "Old Song", isPlaying: true)
        let newTrack = makeTrack(id: "new", name: "New Song", isPlaying: true)
        let oldSnapshot = readySnapshot(oldTrack)
        let oldLyrics = syncedLyrics(prefix: "old")
        let newLyrics = syncedLyrics(prefix: "new")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in oldLyrics },
            nowPlayingSnapshotOverride: { oldSnapshot },
            artworkImageOverride: { _, _ in
                await artworkGate.suspend()
                return nil
            },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let oldKey = trackKey(oldSnapshot)
        let newSnapshot = readySnapshot(newTrack)

        model.lastTrackKey = oldKey
        model.nowPlaying = oldSnapshot
        let task = model.startLyricsFetch(
            for: oldTrack,
            trackKey: oldKey,
            alsoArtwork: true
        )
        await artworkGate.waitUntilSuspended()

        model.lastTrackKey = trackKey(newSnapshot)
        model.nowPlaying = newSnapshot
        model.lyrics = newLyrics
        await artworkGate.resume()
        await task.value

        XCTAssertNil(model.offsetCalibrationStatusText)
        XCTAssertEqual(model.lyrics, newLyrics)
    }

    @MainActor
    func testNowPlayingChangeBeforeTrackKeyUpdateStopsStaleLyricsSideEffects() async {
        let artworkGate = SuspensionGate()
        let oldTrack = makeTrack(id: "old-window", name: "Old Window Song", isPlaying: true)
        let newTrack = makeTrack(id: "new-window", name: "New Window Song", isPlaying: true)
        let oldSnapshot = readySnapshot(oldTrack)
        let newSnapshot = readySnapshot(newTrack)
        let oldLyrics = syncedLyrics(prefix: "old-window")
        let newLyrics = syncedLyrics(prefix: "new-window")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in oldLyrics },
            nowPlayingSnapshotOverride: { oldSnapshot },
            artworkImageOverride: { _, _ in
                await artworkGate.suspend()
                return nil
            },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let oldKey = trackKey(oldSnapshot)

        model.lastTrackKey = oldKey
        model.nowPlaying = oldSnapshot
        let task = model.startLyricsFetch(
            for: oldTrack,
            trackKey: oldKey,
            alsoArtwork: true
        )
        await artworkGate.waitUntilSuspended()

        // Mirrors tick(): nowPlaying changes before the later lastTrackKey assignment.
        model.nowPlaying = newSnapshot
        model.lyrics = newLyrics
        await artworkGate.resume()
        await task.value

        XCTAssertNil(model.offsetCalibrationStatusText)
        XCTAssertEqual(model.lyrics, newLyrics)
    }

    @MainActor
    func testFreshSnapshotForDifferentTrackStopsOldTrackCalibration() async {
        let oldTrack = makeTrack(id: "old-fresh", name: "Old Fresh Song", isPlaying: true)
        let newTrack = makeTrack(id: "new-fresh", name: "New Fresh Song", isPlaying: true)
        let oldSnapshot = readySnapshot(oldTrack)
        let newSnapshot = readySnapshot(newTrack)
        let oldLyrics = syncedLyrics(prefix: "old-fresh")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in oldLyrics },
            nowPlayingSnapshotOverride: { newSnapshot },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let oldKey = trackKey(oldSnapshot)

        model.lastTrackKey = oldKey
        model.nowPlaying = oldSnapshot
        let task = model.startLyricsFetch(
            for: oldTrack,
            trackKey: oldKey,
            alsoArtwork: false
        )
        await task.value

        XCTAssertNil(model.offsetCalibrationStatusText)
        XCTAssertEqual(model.nowPlaying, oldSnapshot)
    }

    @MainActor
    func testLyricsRefreshSnapshotCannotReplaceNewerSameTrackSample() async {
        let snapshotGate = SuspensionGate()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let staleTrack = makeTrack(
            id: "same-sample",
            name: "Same Song",
            isPlaying: true,
            position: 20,
            positionSampledAt: t0
        )
        let newerTrack = makeTrack(
            id: "same-sample",
            name: "Same Song",
            isPlaying: true,
            position: 23,
            positionSampledAt: t0.addingTimeInterval(3)
        )
        let staleSnapshot = readySnapshot(staleTrack)
        let newerSnapshot = readySnapshot(newerTrack)
        let fetchedLyrics = syncedLyrics(prefix: "same-sample")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in fetchedLyrics },
            nowPlayingSnapshotOverride: {
                await snapshotGate.suspend()
                return staleSnapshot
            },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let key = trackKey(staleSnapshot)
        model.lastTrackKey = key
        model.nowPlaying = staleSnapshot

        let task = model.startLyricsFetch(
            for: staleTrack,
            trackKey: key,
            alsoArtwork: false
        )
        await snapshotGate.waitUntilSuspended()
        model.nowPlaying = newerSnapshot
        await snapshotGate.resume()
        await task.value

        XCTAssertEqual(model.nowPlaying, newerSnapshot)
    }

    @MainActor
    func testForcedFetchUsesFreshPausedTrackForBlockedStatus() async {
        let playingTrack = makeTrack(
            id: "fresh-paused",
            name: "Fresh Paused Song",
            isPlaying: true
        )
        let pausedTrack = makeTrack(
            id: "fresh-paused",
            name: "Fresh Paused Song",
            isPlaying: false
        )
        let playingSnapshot = readySnapshot(playingTrack)
        let pausedSnapshot = readySnapshot(pausedTrack)
        let fetchedLyrics = syncedLyrics(prefix: "fresh-paused")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in fetchedLyrics },
            nowPlayingSnapshotOverride: { pausedSnapshot },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(playingSnapshot)
        model.nowPlaying = playingSnapshot
        model.lyrics = .skipped

        model.recalibrateCurrentTrackOffset()
        let completed = await waitUntil {
            model.offsetCalibrationStatusText != L10n.t("offset_cal.waiting_lyrics")
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.skip_paused"))
    }

    @MainActor
    func testForcedFetchWithUnavailableFreshSnapshotLeavesRetryableStatus() async {
        let track = makeTrack(
            id: "fresh-unavailable",
            name: "Fresh Unavailable Song",
            isPlaying: true
        )
        let snapshot = readySnapshot(track)
        let fetchedLyrics = syncedLyrics(prefix: "fresh-unavailable")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in fetchedLyrics },
            nowPlayingSnapshotOverride: {
                NowPlayingSnapshot(availability: .error, detail: "transient")
            },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = .skipped

        model.recalibrateCurrentTrackOffset()
        let completed = await waitUntil {
            !model.isFetchingLyrics
                && model.offsetCalibrationStatusText != L10n.t("offset_cal.waiting_lyrics")
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.need_playing"))

        // The fetched lyrics remain usable, so the user can retry on the same ready track.
        model.recalibrateCurrentTrackOffset()
        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.skip_headphones"))
    }

    @MainActor
    func testForcedRecalibrationWhilePausedShowsPausedStatus() {
        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        let track = makeTrack(id: "paused", name: "Paused Song", isPlaying: false)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = syncedLyrics(prefix: "paused")

        model.recalibrateCurrentTrackOffset()

        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.skip_paused"))
    }

    @MainActor
    func testForcedRecalibrationWhilePausedDoesNotWaitForMissingLyrics() {
        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        let track = makeTrack(id: "paused-no-lyrics", name: "Paused Song", isPlaying: false)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = .skipped

        model.recalibrateCurrentTrackOffset()

        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.skip_paused"))
        XCTAssertFalse(model.isFetchingLyrics)
    }

    @MainActor
    func testForcedRecalibrationWithTooFewUsableLinesShowsFewLinesStatus() {
        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        let track = makeTrack(id: "short", name: "Short Song", isPlaying: true)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 1, text: "one"),
                LyricLine(time: 2, text: "two"),
                LyricLine(time: 3, text: "   ")
            ]
        )

        model.recalibrateCurrentTrackOffset()

        XCTAssertEqual(
            model.offsetCalibrationStatusText,
            L10n.t("offset_cal.too_few_timed_lines", 2)
        )
        XCTAssertTrue(model.shouldOfferSyncedLyricsSearch)
    }

    @MainActor
    func testStackedTranslationsDoNotQualifyAsThreeCalibrationLines() {
        let model = AppModel(
            store: .ephemeral(),
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let track = makeTrack(id: "stacked", name: "Stacked Song", isPlaying: true)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 12, text: "original"),
                LyricLine(time: 12, text: "translation"),
                LyricLine(time: 12.08, text: "romanization")
            ]
        )

        model.recalibrateCurrentTrackOffset()

        XCTAssertEqual(
            model.offsetCalibrationStatusText,
            L10n.t("offset_cal.too_few_timed_lines", 1)
        )
        XCTAssertTrue(model.shouldOfferSyncedLyricsSearch)
    }

    @MainActor
    func testForcedRecalibrationWithPlainLyricsExplainsMissingTimeline() async {
        let track = makeTrack(id: "plain", name: "Plain Song", isPlaying: true)
        let snapshot = readySnapshot(track)
        let plainLyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["one", "two", "three"],
            source: "LRCLIB"
        )
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in plainLyrics },
            nowPlayingSnapshotOverride: { snapshot },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = plainLyrics

        model.recalibrateCurrentTrackOffset()
        let completed = await waitUntil {
            !model.isFetchingLyrics
                && model.offsetCalibrationStatusText != L10n.t("offset_cal.waiting_lyrics")
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(
            model.offsetCalibrationStatusText,
            L10n.t("offset_cal.no_timed_lyrics")
        )
        XCTAssertTrue(model.shouldOfferSyncedLyricsSearch)
    }

    @MainActor
    func testSyncedLyricsDoNotOfferReplacementSearchEntry() {
        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        let track = makeTrack(id: "synced-entry", name: "Synced Song", isPlaying: true)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = syncedLyrics(prefix: "synced-entry")

        XCTAssertFalse(model.shouldOfferSyncedLyricsSearch)
    }

    @MainActor
    func testLocalLRCImportReplacesPlainTimelineAndReportsUsableCount() async throws {
        let track = makeTrack(id: "local-import", name: "Local Import", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: .ephemeral(),
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["one", "two", "three"],
            source: "lrclib"
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-appmodel-\(UUID().uuidString).lrc")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data("[00:01.00]one\n[00:05.00]two\n[00:09.00]three\n".utf8)
            .write(to: fileURL)

        model.importLocalLRC(from: fileURL)
        let completed = await waitUntil { !model.isImportingLocalLRC }

        XCTAssertTrue(completed)
        XCTAssertEqual(model.lyrics.availability, .synced)
        XCTAssertEqual(model.lyrics.source, LocalLRCImporter.sourceIdentifier)
        XCTAssertEqual(model.lyrics.lines.count, 3)
        XCTAssertEqual(
            model.lyricsTimelineOperationStatusText,
            L10n.t("lrc_import.success", fileURL.lastPathComponent, 3)
        )
    }

    @MainActor
    func testTapSyncRecordCancelsSuspendedLocalImportWithoutLeavingBusyState() async throws {
        let importGate = SuspensionGate()
        let track = makeTrack(id: "tap-cancels-import", name: "Tap Cancels Import", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: .ephemeral(),
            localLRCImportOverride: { url in
                await importGate.suspend()
                return try LocalLRCImporter().load(from: url)
            },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second", "third"],
            source: "lrclib"
        )
        model.prepareTapSync()

        let fileURL = try makeTemporaryLRC()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        model.importLocalLRC(from: fileURL)
        await importGate.waitUntilSuspended()
        XCTAssertTrue(model.isImportingLocalLRC)

        model.recordTapSyncAnchorNow()

        XCTAssertFalse(model.isImportingLocalLRC)
        XCTAssertEqual(model.tapSyncAnchorCount, 1)
        XCTAssertEqual(model.lyrics.source, TapSyncProject.outputSource)
        let tapStatus = model.lyricsTimelineOperationStatusText

        await importGate.resume()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(model.isImportingLocalLRC)
        XCTAssertEqual(model.lyrics.source, TapSyncProject.outputSource)
        XCTAssertEqual(model.lyricsTimelineOperationStatusText, tapStatus)
    }

    @MainActor
    func testTapSyncUndoCancelsSuspendedLocalImportWithoutOverwritingStatus() async throws {
        let importGate = SuspensionGate()
        let track = makeTrack(id: "undo-cancels-import", name: "Undo Cancels Import", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: .ephemeral(),
            localLRCImportOverride: { url in
                await importGate.suspend()
                return try LocalLRCImporter().load(from: url)
            },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second", "third"],
            source: "lrclib"
        )
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()

        let fileURL = try makeTemporaryLRC()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        model.importLocalLRC(from: fileURL)
        await importGate.waitUntilSuspended()

        model.undoTapSyncAnchor()

        XCTAssertFalse(model.isImportingLocalLRC)
        XCTAssertEqual(model.tapSyncAnchorCount, 0)
        let undoStatus = model.lyricsTimelineOperationStatusText

        await importGate.resume()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(model.isImportingLocalLRC)
        XCTAssertNotEqual(model.lyrics.source, LocalLRCImporter.sourceIdentifier)
        XCTAssertEqual(model.lyricsTimelineOperationStatusText, undoStatus)
    }

    @MainActor
    func testTapSyncRecordsDraftAppliesSegmentedTimelineAndPersistsProject() {
        let tapStore = TapSyncProjectStore.ephemeral()
        let track = makeTrack(id: "tap-draft", name: "Tap Draft", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: tapStore,
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second", "third"],
            source: "lrclib"
        )

        model.prepareTapSync()
        XCTAssertEqual(model.tapSyncSelectedLineIndex, 0)
        model.recordTapSyncAnchorNow()

        XCTAssertEqual(model.tapSyncAnchorCount, 1)
        XCTAssertEqual(model.lyrics.availability, .synced)
        XCTAssertEqual(model.lyrics.source, TapSyncProject.outputSource)
        XCTAssertEqual(model.lyrics.lines.count, 3)
        let stored = tapStore.latest(for: track, source: .spotify)
        XCTAssertEqual(stored?.anchors.count, 1)

        model.finishTapSync()
        XCTAssertEqual(
            model.tapSyncStatusText,
            L10n.t("tap_sync.saved_partial", 1, 3)
        )
    }

    @MainActor
    func testTapSyncRejectsActionsAfterTrackChangeWithoutCrossApplyingAnchors() {
        let tapStore = TapSyncProjectStore.ephemeral()
        let oldTrack = makeTrack(id: "tap-old", name: "Tap Old", isPlaying: true)
        let newTrack = makeTrack(id: "tap-new", name: "Tap New", isPlaying: true)
        let oldSnapshot = readySnapshot(oldTrack)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: tapStore,
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(oldSnapshot)
        model.nowPlaying = oldSnapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second", "third"],
            source: "lrclib"
        )
        model.prepareTapSync()

        model.nowPlaying = readySnapshot(newTrack)
        model.recordTapSyncAnchorNow()

        XCTAssertNil(model.tapSyncProject)
        XCTAssertEqual(model.tapSyncStatusText, L10n.t("tap_sync.track_changed"))
        XCTAssertNil(tapStore.latest(for: newTrack, source: .spotify))
        XCTAssertEqual(tapStore.latest(for: oldTrack, source: .spotify)?.anchors.count, 0)
    }

    @MainActor
    func testTapSyncRejectsSameTrackLyricsFingerprintChange() {
        let tapStore = TapSyncProjectStore.ephemeral()
        let track = makeTrack(id: "tap-lyrics-change", name: "Tap Lyrics Change", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            tapSyncStore: tapStore,
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["old first", "old second"],
            source: "provider-a"
        )
        model.prepareTapSync()

        let replacement = LyricsSnapshot(
            availability: .plain,
            plainLines: ["new first", "new second"],
            source: "provider-b"
        )
        model.lyrics = replacement
        model.recordTapSyncAnchorNow()

        XCTAssertNil(model.tapSyncProject)
        XCTAssertEqual(model.tapSyncStatusText, L10n.t("tap_sync.lyrics_changed"))
        XCTAssertEqual(model.lyrics, replacement)
        XCTAssertEqual(tapStore.latest(for: track, source: .spotify)?.anchors.count, 0)
    }

    @MainActor
    func testUseAutomaticLyricsRemovalSurvivesImmediateTrackChange() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let lyricsService = LyricsService(pinnedLyricsStore: pinnedStore)
        let oldTrack = makeTrack(id: "auto-old", name: "Automatic Old", isPlaying: true)
        let newTrack = makeTrack(id: "auto-new", name: "Automatic New", isPlaying: true)
        let selected = LyricsSnapshot(
            availability: .plain,
            plainLines: ["old first", "old second"],
            source: "manual-search",
            selectionReason: .manuallySelected
        )
        await lyricsService.setPlayerSource(.spotify)
        _ = await lyricsService.apply(manualSnapshot: selected, to: oldTrack)
        XCTAssertNotNil(pinnedStore.snapshot(for: oldTrack, source: .spotify))

        let model = AppModel(
            store: .ephemeral(),
            lyricsService: lyricsService,
            tapSyncStore: .ephemeral(),
            rendersOverlay: false
        )
        let oldSnapshot = readySnapshot(oldTrack)
        model.lastTrackKey = trackKey(oldSnapshot)
        model.nowPlaying = oldSnapshot
        model.lyrics = selected

        model.useAutomaticLyrics()

        let newSnapshot = readySnapshot(newTrack)
        model.nowPlaying = newSnapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["new first", "new second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        await model.waitForManualTimelinePersistence()

        XCTAssertNil(pinnedStore.snapshot(for: oldTrack, source: .spotify))
    }

    @MainActor
    func testTapSyncResetRemovalSurvivesImmediateTrackChange() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let lyricsService = LyricsService(pinnedLyricsStore: pinnedStore)
        let tapStore = TapSyncProjectStore.ephemeral()
        let oldTrack = makeTrack(id: "reset-old", name: "Reset Old", isPlaying: true)
        let newTrack = makeTrack(id: "reset-new", name: "Reset New", isPlaying: true)
        let selected = LyricsSnapshot(
            availability: .plain,
            plainLines: ["old first", "old second"],
            source: "lrclib"
        )

        let model = AppModel(
            store: .ephemeral(),
            lyricsService: lyricsService,
            tapSyncStore: tapStore,
            rendersOverlay: false
        )
        let oldSnapshot = readySnapshot(oldTrack)
        model.lastTrackKey = trackKey(oldSnapshot)
        model.nowPlaying = oldSnapshot
        model.lyrics = selected
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()
        await model.waitForManualTimelinePersistence()
        XCTAssertEqual(
            pinnedStore.snapshot(for: oldTrack, source: .spotify)?.source,
            TapSyncProject.outputSource
        )

        model.resetTapSyncProject()

        let newSnapshot = readySnapshot(newTrack)
        model.nowPlaying = newSnapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["new first", "new second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        await model.waitForManualTimelinePersistence()

        XCTAssertNil(pinnedStore.snapshot(for: oldTrack, source: .spotify))
    }

    @MainActor
    func testTapSyncUndoReplacesPreviouslyPersistedFinishedTimeline() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let lyricsService = LyricsService(pinnedLyricsStore: pinnedStore)
        let track = makeTrack(id: "undo-finished", name: "Undo Finished", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            lyricsService: lyricsService,
            tapSyncStore: .ephemeral(),
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()
        model.finishTapSync()
        await model.waitForManualTimelinePersistence()
        XCTAssertEqual(
            pinnedStore.snapshot(for: track, source: .spotify)?.source,
            TapSyncProject.outputSource
        )

        model.undoTapSyncAnchor()
        await model.waitForManualTimelinePersistence()

        XCTAssertNil(pinnedStore.snapshot(for: track, source: .spotify))
    }

    @MainActor
    func testReopeningSameTapSyncProjectPreservesPerTrackCorrection() async {
        let offsetStore = TrackLyricOffsetStore.ephemeral()
        let tapStore = TapSyncProjectStore.ephemeral()
        let track = makeTrack(id: "reopen-offset", name: "Reopen Offset", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            trackOffsetStore: offsetStore,
            tapSyncStore: tapStore,
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()
        await model.waitForManualTimelinePersistence()
        model.endTapSyncSession()
        model.nudgeTrackAutoOffset(by: 0.5)
        XCTAssertEqual(model.trackLyricOffsetSeconds, 0.5, accuracy: 0.001)

        model.prepareTapSync()

        XCTAssertEqual(model.trackLyricOffsetSeconds, 0.5, accuracy: 0.001)
        let stored = offsetStore.offset(
            for: model.nowPlaying.track,
            source: model.nowPlaying.source
        )
        XCTAssertEqual(stored?.offsetSeconds ?? 0, 0.5, accuracy: 0.001)
    }

    @MainActor
    func testNewTapSyncMutationAfterClearStoredDataWinsInActionOrder() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let lyricsService = LyricsService(pinnedLyricsStore: pinnedStore)
        let track = makeTrack(id: "clear-then-tap", name: "Clear Then Tap", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            lyricsService: lyricsService,
            tapSyncStore: .ephemeral(),
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot

        model.clearStoredLyricsAndOffsets()
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()
        await model.waitForManualTimelinePersistence()

        XCTAssertEqual(
            pinnedStore.snapshot(for: track, source: .spotify)?.source,
            TapSyncProject.outputSource
        )
    }

    @MainActor
    func testClearStoredDataAfterTapSyncMutationWinsInActionOrder() async {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let lyricsService = LyricsService(pinnedLyricsStore: pinnedStore)
        let track = makeTrack(id: "tap-then-clear", name: "Tap Then Clear", isPlaying: true)
        let snapshot = readySnapshot(track)
        let model = AppModel(
            store: .ephemeral(),
            lyricsService: lyricsService,
            tapSyncStore: .ephemeral(),
            lyricsSnapshotOverride: { _ in .skipped },
            nowPlayingSnapshotOverride: { snapshot },
            artworkImageOverride: { _, _ in nil },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .plain,
            plainLines: ["first", "second"],
            source: "lrclib"
        )
        model.prepareTapSync()
        model.recordTapSyncAnchorNow()

        model.clearStoredLyricsAndOffsets()
        await model.waitForManualTimelinePersistence()

        XCTAssertNil(pinnedStore.snapshot(for: track, source: .spotify))
    }

    @MainActor
    func testManualTapTimelineDoesNotStartMicrophoneRecalibration() {
        let model = AppModel(store: .ephemeral(), rendersOverlay: false)
        let track = makeTrack(id: "manual-tap", name: "Manual Tap", isPlaying: true)
        let snapshot = readySnapshot(track)
        model.lastTrackKey = trackKey(snapshot)
        model.nowPlaying = snapshot
        model.lyrics = LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 1, text: "one"),
                LyricLine(time: 5, text: "two"),
                LyricLine(time: 9, text: "three")
            ],
            source: TapSyncProject.outputSource,
            timingBaseFingerprint: "base"
        )

        model.recalibrateCurrentTrackOffset()

        XCTAssertEqual(
            model.offsetCalibrationStatusText,
            L10n.t("offset_cal.manual_timeline")
        )
    }

    func testCalibrationActionMessagesExistInEveryLocalization() {
        let keys = [
            "button.search_synced_lyrics",
            "help.search_synced_lyrics",
            "offset_cal.no_timed_lyrics",
            "offset_cal.too_few_timed_lines",
            "offset_cal.sparse_window"
        ]
        let tables = [L10n.zhHant, L10n.zhHans, L10n.en, L10n.ja]

        for table in tables {
            for key in keys {
                XCTAssertNotNil(table[key], "Missing localization key: \(key)")
            }
        }
    }

    @MainActor
    func testStoredOffsetLoadsOnlyAfterMatchingLyricsTimelineArrives() async {
        let track = makeTrack(id: "stored-match", name: "Stored Match", isPlaying: true)
        let snapshot = readySnapshot(track)
        let fetchedLyrics = syncedLyrics(prefix: "stored-match")
        let offsetStore = TrackLyricOffsetStore.ephemeral()
        let fingerprint = try! XCTUnwrap(
            fetchedLyrics.timelineFingerprint(duration: track.duration)
        )
        offsetStore.set(
            TrackLyricOffsetEntry(
                offsetSeconds: 0.75,
                confidence: 0.9,
                source: "auto",
                lyricsFingerprint: fingerprint,
                audioRoute: AudioOutputProbe.Route.speakers.rawValue
            ),
            forTrackKey: TrackLyricOffsetStore.trackKey(for: track)
        )
        let model = AppModel(
            store: .ephemeral(),
            trackOffsetStore: offsetStore,
            lyricsSnapshotOverride: { _ in fetchedLyrics },
            nowPlayingSnapshotOverride: { snapshot },
            micCalibrationLikelyUsefulOverride: { false },
            audioOutputRouteOverride: { .speakers },
            rendersOverlay: false
        )
        let key = trackKey(snapshot)
        model.lastTrackKey = key
        model.nowPlaying = snapshot

        XCTAssertNil(model.currentTrackAutoOffsetSeconds)
        await model.startLyricsFetch(for: track, trackKey: key, alsoArtwork: false).value

        XCTAssertEqual(model.currentTrackAutoOffsetSeconds ?? .nan, 0.75, accuracy: 0.000_1)
    }

    @MainActor
    func testLyricsProviderChangeRetiresStoredOffsetForSameTrack() async {
        let track = makeTrack(id: "stored-mismatch", name: "Stored Mismatch", isPlaying: true)
        let snapshot = readySnapshot(track)
        let oldLyrics = syncedLyrics(prefix: "old-provider")
        let newLyrics = syncedLyrics(prefix: "new-provider")
        let offsetStore = TrackLyricOffsetStore.ephemeral()
        offsetStore.set(
            TrackLyricOffsetEntry(
                offsetSeconds: -0.6,
                confidence: 0.9,
                source: "auto",
                lyricsFingerprint: oldLyrics.timelineFingerprint(duration: track.duration),
                audioRoute: AudioOutputProbe.Route.speakers.rawValue
            ),
            forTrackKey: TrackLyricOffsetStore.trackKey(for: track)
        )
        let model = AppModel(
            store: .ephemeral(),
            trackOffsetStore: offsetStore,
            lyricsSnapshotOverride: { _ in newLyrics },
            nowPlayingSnapshotOverride: { snapshot },
            micCalibrationLikelyUsefulOverride: { false },
            audioOutputRouteOverride: { .speakers },
            rendersOverlay: false
        )
        let key = trackKey(snapshot)
        model.lastTrackKey = key
        model.nowPlaying = snapshot

        await model.startLyricsFetch(for: track, trackKey: key, alsoArtwork: false).value

        XCTAssertNil(model.currentTrackAutoOffsetSeconds)
        XCTAssertNil(
            offsetStore.offset(forTrackKey: TrackLyricOffsetStore.trackKey(for: track))
        )
    }

    @MainActor
    func testPlaybackResumeRevisitsCalibrationForSameTrack() async {
        let pausedTrack = makeTrack(
            id: "resume-calibration",
            name: "Resume Calibration",
            isPlaying: false
        )
        let playingTrack = makeTrack(
            id: "resume-calibration",
            name: "Resume Calibration",
            isPlaying: true
        )
        let pausedSnapshot = readySnapshot(pausedTrack)
        let playingSnapshot = readySnapshot(playingTrack)
        let store = PreferencesStore.ephemeral()
        var preferences = store.load()
        preferences.autoCalibrateLyricOffset = true
        store.save(preferences)
        let model = AppModel(
            store: store,
            nowPlayingSnapshotOverride: { playingSnapshot },
            artworkImageOverride: { _, _ in nil },
            micCalibrationLikelyUsefulOverride: { false },
            audioOutputRouteOverride: { .speakers },
            rendersOverlay: false
        )
        model.lastTrackKey = trackKey(pausedSnapshot)
        model.nowPlaying = pausedSnapshot
        model.lyrics = syncedLyrics(prefix: "resume")

        await model.tick()

        XCTAssertEqual(model.offsetCalibrationStatusText, L10n.t("offset_cal.skip_headphones"))
    }

    @MainActor
    func testManualLyricsSelectionCannotBeOverwrittenBySameTrackFetch() async {
        let fetchGate = SuspensionGate()
        let track = makeTrack(id: "manual-wins", name: "Manual Wins", isPlaying: true)
        let snapshot = readySnapshot(track)
        let automaticLyrics = syncedLyrics(prefix: "automatic")
        let manualLyrics = syncedLyrics(prefix: "manual")
        let model = AppModel(
            store: .ephemeral(),
            lyricsSnapshotOverride: { _ in
                await fetchGate.suspend()
                return automaticLyrics
            },
            nowPlayingSnapshotOverride: { snapshot },
            artworkImageOverride: { _, _ in nil },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        let key = trackKey(snapshot)
        model.lastTrackKey = key
        model.nowPlaying = snapshot
        model.prepareLyricsSearch()
        let automaticTask = model.startLyricsFetch(
            for: track,
            trackKey: key,
            alsoArtwork: false
        )
        await fetchGate.waitUntilSuspended()

        model.applyLyricsSearchHit(
            LyricsSearchHit(
                id: "manual-hit",
                trackName: track.name,
                artistName: track.artist,
                duration: track.duration,
                hasSynced: true,
                sourceLabel: "manual",
                snapshot: manualLyrics
            )
        )
        let manualApplied = await waitUntil {
            model.lyrics.selectionReason == .manuallySelected
        }
        XCTAssertTrue(manualApplied)

        await fetchGate.resume()
        await automaticTask.value

        XCTAssertEqual(model.lyrics.selectionReason, .manuallySelected)
        XCTAssertEqual(model.lyrics.lines.first?.text, "manual one")
    }

    @MainActor
    func testTransientPlayerErrorsPreserveLastReadyTrackUntilThirdFailure() async {
        let track = makeTrack(id: "stable", name: "Stable Song", isPlaying: true)
        let ready = readySnapshot(track)
        let sequence = SnapshotSequence([
            NowPlayingSnapshot(availability: .error, detail: "timeout 1"),
            NowPlayingSnapshot(availability: .error, detail: "timeout 2"),
            NowPlayingSnapshot(availability: .error, detail: "timeout 3")
        ])
        let model = AppModel(
            store: .ephemeral(),
            nowPlayingSnapshotOverride: { await sequence.next() },
            artworkImageOverride: { _, _ in nil },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        model.nowPlaying = ready
        model.lastTrackKey = trackKey(ready)
        model.lyrics = syncedLyrics(prefix: "stable")

        await model.tick()
        XCTAssertEqual(model.nowPlaying, ready)
        XCTAssertEqual(model.lyrics.lines.first?.text, "stable one")
        XCTAssertEqual(model.playbackWarning, "timeout 1")

        await model.tick()
        XCTAssertEqual(model.nowPlaying, ready)
        XCTAssertEqual(model.playbackWarning, "timeout 2")

        await model.tick()
        XCTAssertEqual(model.nowPlaying.availability, .error)
        XCTAssertEqual(model.playbackWarning, "timeout 3")
    }

    @MainActor
    func testMissingArtworkUsesNegativeBackoffAcrossPolls() async {
        let track = makeTrack(id: "no-art", name: "No Artwork", isPlaying: true)
        let snapshot = readySnapshot(track)
        let counter = AsyncCounter()
        let model = AppModel(
            store: .ephemeral(),
            nowPlayingSnapshotOverride: { snapshot },
            artworkImageOverride: { _, _ in
                await counter.increment()
                return nil
            },
            micCalibrationLikelyUsefulOverride: { false },
            rendersOverlay: false
        )
        model.nowPlaying = snapshot
        model.lastTrackKey = trackKey(snapshot)

        await model.tick()
        await model.tick()

        let fetchCount = await counter.value()
        XCTAssertEqual(fetchCount, 1)
    }

    private func makeTrack(
        id: String,
        name: String,
        isPlaying: Bool,
        position: TimeInterval = 20,
        positionSampledAt: Date? = nil
    ) -> Track {
        Track(
            id: id,
            name: name,
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: position,
            isPlaying: isPlaying,
            positionSampledAt: positionSampledAt
        )
    }

    private func readySnapshot(_ track: Track) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            availability: .ready,
            track: track,
            source: .spotify
        )
    }

    private func syncedLyrics(prefix: String) -> LyricsSnapshot {
        LyricsSnapshot(
            availability: .synced,
            lines: [
                LyricLine(time: 1, text: "\(prefix) one"),
                LyricLine(time: 5, text: "\(prefix) two"),
                LyricLine(time: 9, text: "\(prefix) three")
            ]
        )
    }

    private func trackKey(_ snapshot: NowPlayingSnapshot) -> String {
        "ready|\(TrackIdentity(track: snapshot.track, source: snapshot.source).storageKey)"
    }

    private func makeTemporaryLRC() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-race-\(UUID().uuidString).lrc")
        try Data("[00:01.00]one\n[00:05.00]two\n[00:09.00]three\n".utf8)
            .write(to: url)
        return url
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private actor SuspensionGate {
    private var didSuspend = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        didSuspend = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !didSuspend {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SnapshotSequence {
    private var snapshots: [NowPlayingSnapshot]

    init(_ snapshots: [NowPlayingSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> NowPlayingSnapshot {
        guard !snapshots.isEmpty else {
            return NowPlayingSnapshot(availability: .error, detail: "sequence exhausted")
        }
        return snapshots.removeFirst()
    }
}

private actor AsyncCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int { count }
}
