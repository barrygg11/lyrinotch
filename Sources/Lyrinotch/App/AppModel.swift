import AppKit
import Foundation
import Observation
import SwiftUI
import LyrinotchCore

/// Coordinates Spotify / Apple Music polling, lyrics, island, prefs, and hotkeys.
@MainActor
@Observable
final class AppModel {
    private enum IslandSyncState {
        case none
        case listening
        case waiting
        case synced
        case useManual
    }

    private enum AutoCalibrationStartResult {
        case started
        case noAction
        case blocked(AutoCalibrationBlockReason)
    }

    private enum AutoCalibrationBlockReason {
        case paused
        case noTimedLyrics
        case tooFewTimedLines(Int)
        case manuallyTimedTimeline
        case headphones
        case calibratorBusy
        case playbackUnavailable
    }

    var nowPlaying = NowPlayingSnapshot.playerNotRunning
    var lyrics = LyricsSnapshot.skipped {
        didSet { lyricsDisplayCache.invalidate() }
    }
    var preferences = AppPreferences.default
    var lastError: String?
    /// Transient player-query warning kept separate from command/settings errors.
    var playbackWarning: String?
    var launchAtLoginStatusText = L10n.t("login.unknown")
    var hotKeyStatusText = L10n.t("hotkey.default")
    /// True while a lyrics network/Music fetch is in flight.
    var isFetchingLyrics = false
    /// Optional translation of the current primary lyric line.
    var currentTranslation: String?
    let lyricsSearch = LyricsSearchState()
    /// Live status for automatic lyric-offset calibration.
    var offsetCalibrationStatusText: String?
    /// Status for local LRC import and manual timeline operations.
    var lyricsTimelineOperationStatusText: String?
    var isImportingLocalLRC = false
    var tapSyncProject: TapSyncProject?
    var tapSyncSelectedLineIndex: Int?
    var tapSyncStatusText: String?
    private var tapSyncTargetTrackKey: String?
    /// Orders local/import/search timeline mutations that may cross an actor hop.
    private var manualTimelineRequestID = 0
    private var localLRCImportTask: Task<Void, Never>?
    private let manualTimelineMutationQueue = ManualTimelineMutationQueue()
    private var islandSyncState: IslandSyncState = .none
    /// Cached auto offset for the current track (seconds), if any.
    var currentTrackAutoOffsetSeconds: Double?
    private var currentTrackOffsetConfidence: Double?
    private var currentTrackOffsetSource: String?
    private var currentTrackOffsetAudioRoute: String?
    /// Live total applied to the lyric playhead (for Settings diagnostics).
    var effectiveLyricOffsetSeconds: Double { effectiveLyricOffset }

    var globalLyricOffsetSeconds: Double { preferences.lyricOffsetSeconds }

    var trackLyricOffsetSeconds: Double { currentTrackAutoOffsetSeconds ?? 0 }

    var canStartTapSync: Bool {
        guard nowPlaying.availability == .ready else { return false }
        if lyrics.availability == .plain, !lyrics.plainLines.isEmpty { return true }
        return lyrics.availability == .synced
            && lyrics.source == TapSyncProject.outputSource
            && tapSyncStore.project(
                for: nowPlaying.track,
                source: nowPlaying.source,
                matching: lyrics
            ) != nil
    }

    var tapSyncPlaybackPosition: TimeInterval {
        playbackClock.position()
    }

    var tapSyncIsPlaying: Bool {
        nowPlaying.availability == .ready
            && (nowPlaying.track.isPlaying || playbackClock.isPlaying)
    }

    var tapSyncAnchorCount: Int { tapSyncProject?.anchors.count ?? 0 }

    var tapSyncUsableLineCount: Int {
        tapSyncProject?.nonEmptyLineIndices.count ?? 0
    }

    var currentTapSyncCoverageText: String? {
        guard nowPlaying.availability == .ready,
              lyrics.source == TapSyncProject.outputSource,
              let project = tapSyncStore.project(
                for: nowPlaying.track,
                source: nowPlaying.source,
                matching: lyrics
              )
        else { return nil }
        return L10n.t(
            "tap_sync.coverage",
            project.anchors.count,
            project.nonEmptyLineIndices.count
        )
    }

    var tapSyncSelectedLineText: String? {
        guard let project = tapSyncProject,
              let index = tapSyncSelectedLineIndex,
              project.lineTexts.indices.contains(index)
        else { return nil }
        return project.lineTexts[index]
    }

    func tapSyncAnchorTime(for lineIndex: Int) -> TimeInterval? {
        tapSyncProject?.anchors.first(where: { $0.lineIndex == lineIndex })?.playbackTime
    }

    /// Whether Settings should offer the existing manual lyrics picker as the
    /// next action. Automatic calibration requires a real timed timeline; a
    /// provider's plain-text estimate cannot be corrected reliably by the mic.
    var shouldOfferSyncedLyricsSearch: Bool {
        guard nowPlaying.availability == .ready, !isFetchingLyrics else { return false }
        return lyrics.availability != .synced || usableTimedLyricTimes.count < 3
    }

    private let nowPlayingService = NowPlayingService()
    private let lyricsService: LyricsService
    private let playbackService = PlaybackService()
    private let artworkService = ArtworkService()
    private let localLRCImporter = LocalLRCImporter()
    private let overlay = NotchOverlayController()
    private let store: PreferencesStore
    private let offsetCalibrator = LyricOffsetCalibrator()
    private let trackOffsetStore: TrackLyricOffsetStore
    private let tapSyncStore: TapSyncProjectStore
    private let lyricsSnapshotOverride: ((Track) async -> LyricsSnapshot)?
    private let nowPlayingSnapshotOverride: (() async -> NowPlayingSnapshot)?
    private let artworkImageOverride: (@MainActor (Track, MusicPlayerSource?) async -> NSImage?)?
    private let localLRCImportOverride: ((URL) async throws -> LocalLRCImportResult)?
    private let micCalibrationLikelyUsefulOverride: (() -> Bool)?
    private let audioOutputRouteOverride: (() -> AudioOutputProbe.Route)?
    private let rendersOverlay: Bool

    private var pollTask: Task<Void, Never>?
    /// Smooth lyric/progress UI between AppleScript polls (~50ms).
    private var displayTickTask: Task<Void, Never>?
    /// Non-blocking lyrics fetch so playback clock keeps advancing.
    private var lyricsFetchTask: Task<Void, Never>?
    /// User requested recalibration while synced lyrics were still being fetched.
    private var forcedCalibrationAfterLyricsFetchKey: String?
    private var tickRequestID = 0
    private var consecutiveNowPlayingErrors = 0
    var lastTrackKey: String?
    /// Tracks that already got a successful auto calibration this session.
    private var calibrationSucceededKeys = Set<String>()
    /// Offset-store key for the in-flight calibration pass.
    private var calibratingOffsetKey: String?
    /// Timeline and route captured when a microphone pass starts. A result is
    /// discarded if either changes before analysis completes.
    private var calibratingLyricsFingerprint: String?
    private var calibratingAudioRoute: String?
    /// Bounded multi-window evidence for the currently calibrating track.
    private var calibrationEvidenceKey: String?
    private var calibrationEvidenceLyricsFingerprint: String?
    private var calibrationEvidenceAudioRoute: String?
    private var calibrationAttemptCount = 0
    private var pendingCalibrationSample: LyricCalibrationSample?
    private var calibrationRetryAllowedWhenPreferenceOff = false
    private var calibrationRetryTask: Task<Void, Never>?
    private var artworkImage: NSImage? {
        didSet { artworkAccent = ArtworkColorSampler.lyricAccent(from: artworkImage) }
    }
    private var artworkAccent: Color?
    private var artworkTrackKey: String?
    private var artworkRetryAfter: Date?
    /// Transient expand after track change or hotkey pulse.
    private var transientExpandUntil: Date?
    private var transientExpandTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private var lastTranslatedSource: String?
    /// Pointer is over the notch island / floating pill (auto expand while true).
    private var isHoveringIsland = false
    /// After user taps ✕ (or hotkey collapse), ignore hover-open until the pointer leaves.
    private var suppressHoverExpand = false
    private let pollIntervalNs: UInt64
    /// Local playhead that interpolates while Spotify/Music polls are sparse / blocked.
    private var playbackClock = PlaybackClock()
    private var lyricsDisplayCache = LyricsDisplayCache()

    var isOverlayVisible: Bool { preferences.isOverlayVisible }
    var appearance: OverlayAppearance { preferences.appearance }

    var effectiveIslandMode: IslandMode {
        if preferences.preferExpanded { return .expanded }
        // Pointer over the notch / floating pill.
        if isHoveringIsland { return .expanded }
        // Brief expand from hotkey / track change / click.
        if let until = transientExpandUntil, Date() < until { return .expanded }
        return .collapsed
    }

    var islandModeLabel: String {
        L10n.t("menu.display", overlay.presentationStyle.localizedName, effectiveIslandMode.localizedName)
    }

    var islandModeSummary: String {
        L10n.t("status.presentation_value", overlay.presentationStyle.localizedName, effectiveIslandMode.localizedName)
    }

    /// Active UI language (also drives `L10n.current`).
    var preferredLanguage: AppLanguage {
        preferences.preferredLanguage
    }

    /// Keep a loaded track visible while paused so the overlay's transport
    /// control can resume playback. Idle or missing tracks remain hidden.
    private var shouldPresentOverlay: Bool {
        guard preferences.isOverlayVisible else { return false }
        if preferences.hideInFullscreen,
           let screen = ScreenSelector.screen(for: preferences.screenPlacement),
           screen.lyrinotchLooksFullscreenOccupied
        {
            return false
        }
        switch nowPlaying.availability {
        case .ready:
            return true
        case .playerNotRunning, .noTrack, .error:
            return false
        }
    }

    init(
        pollIntervalMs: Int = 800,
        store: PreferencesStore = PreferencesStore(),
        lyricsService: LyricsService = LyricsService(),
        trackOffsetStore: TrackLyricOffsetStore = TrackLyricOffsetStore(),
        tapSyncStore: TapSyncProjectStore = TapSyncProjectStore(),
        lyricsSnapshotOverride: ((Track) async -> LyricsSnapshot)? = nil,
        nowPlayingSnapshotOverride: (() async -> NowPlayingSnapshot)? = nil,
        artworkImageOverride: (@MainActor (Track, MusicPlayerSource?) async -> NSImage?)? = nil,
        localLRCImportOverride: ((URL) async throws -> LocalLRCImportResult)? = nil,
        micCalibrationLikelyUsefulOverride: (() -> Bool)? = nil,
        audioOutputRouteOverride: (() -> AudioOutputProbe.Route)? = nil,
        rendersOverlay: Bool = true
    ) {
        self.pollIntervalNs = UInt64(max(200, pollIntervalMs)) * 1_000_000
        self.store = store
        self.lyricsService = lyricsService
        self.trackOffsetStore = trackOffsetStore
        self.tapSyncStore = tapSyncStore
        self.lyricsSnapshotOverride = lyricsSnapshotOverride
        self.nowPlayingSnapshotOverride = nowPlayingSnapshotOverride
        self.artworkImageOverride = artworkImageOverride
        self.localLRCImportOverride = localLRCImportOverride
        self.micCalibrationLikelyUsefulOverride = micCalibrationLikelyUsefulOverride
        self.audioOutputRouteOverride = audioOutputRouteOverride
        self.rendersOverlay = rendersOverlay
        var loadedPreferences = store.load()
        let normalizedSource = loadedPreferences.lyricsSourcePreference.normalizedForSettings
        if normalizedSource != loadedPreferences.lyricsSourcePreference {
            loadedPreferences.lyricsSourcePreference = normalizedSource
            store.save(loadedPreferences)
        }
        self.preferences = loadedPreferences
        L10n.apply(preferences.preferredLanguage)
        wireOffsetCalibrator()
        Task {
            await lyricsService.setPreference(preferences.lyricsSourcePreference)
        }
        if rendersOverlay {
            wireOverlayCallbacks()
        }
        if rendersOverlay {
            applyOverlayPreferences()
        }
        refreshLaunchAtLoginStatus()
        refreshLocalizedStatusTexts()
    }

    func setPreferredLanguage(_ language: AppLanguage) {
        guard preferences.preferredLanguage != language else { return }
        preferences.preferredLanguage = language
        L10n.apply(language)
        persist()
        refreshLocalizedStatusTexts()
    }

    /// Re-localize status lines after language change (hotkey monitor stays as-is).
    private func refreshLocalizedStatusTexts() {
        refreshLaunchAtLoginStatus()
        if preferences.hotKeyEnabled {
            // Before `start()`, monitor may not be registered yet.
            if GlobalHotKeyMonitor.shared.isRegistered {
                hotKeyStatusText = L10n.t("hotkey.on")
            } else {
                hotKeyStatusText = L10n.t("hotkey.default")
            }
        } else {
            hotKeyStatusText = L10n.t("hotkey.off")
        }
    }

    func start() {
        guard pollTask == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        configureHotKey()
        if preferences.launchAtLogin, !LaunchAtLogin.isEnabled {
            _ = LaunchAtLogin.setEnabled(true)
            refreshLaunchAtLoginStatus()
        }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: self.currentPollIntervalNs)
            }
        }
        // Keep lyrics line + progress bar in sync with wall clock while playing,
        // even when the next AppleScript poll is still hundreds of ms away.
        displayTickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.playbackClock.isPlaying, self.shouldPresentOverlay {
                    // The visible lyric can change between the slower player
                    // polls. Advance translation state on the same 20 Hz clock
                    // so an old translation is never held under a new line.
                    if self.preferences.showTranslation {
                        self.refreshTranslationIfNeeded()
                    }
                    self.pushOverlay()
                }
                // 20 Hz keeps the visible line-change error below one typical
                // video frame pair without continuously redrawing at 60 Hz.
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Active playback remains responsive; paused and idle states back off to
    /// avoid continuously spawning AppleScript processes while nothing changes.
    private var currentPollIntervalNs: UInt64 {
        switch nowPlaying.availability {
        case .ready where nowPlaying.track.isPlaying:
            return pollIntervalNs
        case .ready:
            return max(pollIntervalNs, 1_500_000_000)
        case .playerNotRunning, .noTrack, .error:
            return max(pollIntervalNs, 2_500_000_000)
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        displayTickTask?.cancel()
        displayTickTask = nil
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        cancelLocalLRCImport()
        lyricsSearch.stop()
        translationTask?.cancel()
        translationTask = nil
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        calibrationRetryTask = nil
        transientExpandTask?.cancel()
        GlobalHotKeyMonitor.shared.stop()
        overlay.shutdown()
    }

    /// Global preference + a confirmed per-track correction.
    private var effectiveLyricOffset: Double {
        preferences.lyricOffsetSeconds
            + (currentTrackAutoOffsetSeconds ?? 0)
    }

    /// Non-empty, finite LRC timestamps that can participate in calibration.
    private var usableTimedLyricTimes: [TimeInterval] {
        let times: [TimeInterval] = lyrics.lines.compactMap { line -> TimeInterval? in
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  line.time.isFinite,
                  line.time >= 0
            else { return nil }
            return line.time
        }
        return LyricOffsetAligner.distinctSingingPointTimes(from: times)
    }

    /// Compact label for the expanded island (short; full text stays in Settings).
    private var islandSyncChipText: String? {
        switch islandSyncState {
        case .none:
            return nil
        case .listening:
            return L10n.t("island.sync_listening")
        case .waiting:
            return L10n.t("island.sync_waiting")
        case .synced:
            return L10n.t("island.sync_ok")
        case .useManual:
            return L10n.t("island.sync_use_manual")
        }
    }

    private var islandSyncSummaryText: String? {
        if lyrics.availability == .plain, !lyrics.plainLines.isEmpty {
            return L10n.t("lyrics.timing_estimated")
        }
        guard islandSyncState == .synced else { return islandSyncChipText }
        switch currentTrackOffsetSource {
        case "auto":
            guard let confidence = currentTrackOffsetConfidence else {
                return islandSyncChipText
            }
            return L10n.t(
                "island.sync_confidence",
                Int((confidence * 100).rounded())
            )
        case "manual", "tap":
            return L10n.t("island.sync_manual")
        default:
            return islandSyncChipText
        }
    }

    private func applyCurrentTrackOffset(_ entry: TrackLyricOffsetEntry?) {
        currentTrackAutoOffsetSeconds = entry?.offsetSeconds
        currentTrackOffsetConfidence = entry?.confidence
        currentTrackOffsetSource = entry?.source
        currentTrackOffsetAudioRoute = entry?.audioRoute
    }

    private var currentAudioCalibrationEnvironment: String {
        if let audioOutputRouteOverride {
            // Keep the legacy route-only override deterministic for unit tests.
            return audioOutputRouteOverride().rawValue
        }
        return AudioOutputProbe.defaultCalibrationEnvironmentIdentity()
    }

    @discardableResult
    private func reloadTrackAutoOffset(for track: Track) -> Bool {
        let key = TrackLyricOffsetStore.trackKey(for: track)
        guard let fingerprint = lyrics.timelineFingerprint(duration: track.duration) else {
            applyCurrentTrackOffset(nil)
            islandSyncState = .none
            return false
        }
        guard let stored = trackOffsetStore.offset(forTrackKey: key) else {
            applyCurrentTrackOffset(nil)
            islandSyncState = .none
            return false
        }
        guard LyricCalibrationPolicy.acceptsStoredOffset(
            stored,
            lyricsFingerprint: fingerprint,
            audioRoute: currentAudioCalibrationEnvironment
        ) else {
            // Retire legacy, stale, wrong-provider, and wrong-route values rather
            // than letting an unrelated timeline correction move these lyrics.
            trackOffsetStore.remove(forTrackKey: key)
            calibrationSucceededKeys.remove(key)
            applyCurrentTrackOffset(nil)
            islandSyncState = .none
            return false
        }
        applyCurrentTrackOffset(stored)
        if stored.source == "auto" {
            calibrationSucceededKeys.insert(key)
        }
        islandSyncState = .synced
        return true
    }

    /// An automatic value includes the acoustic latency of the route used while
    /// recording it. Drop it promptly when the route changes mid-track.
    private func invalidateAutomaticOffsetIfAudioRouteChanged(for track: Track) {
        guard currentTrackOffsetSource == "auto",
              let measuredRoute = currentTrackOffsetAudioRoute,
              measuredRoute != currentAudioCalibrationEnvironment
        else { return }

        let key = TrackLyricOffsetStore.trackKey(for: track)
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence()
        calibrationSucceededKeys.remove(key)
        trackOffsetStore.remove(forTrackKey: key)
        applyCurrentTrackOffset(nil)
        islandSyncState = .none
    }

    private func stopOffsetCalibrationIfActive() {
        switch offsetCalibrator.state {
        case .requestingPermission, .waitingForLyrics, .listening:
            offsetCalibrator.stop()
        case .idle, .succeeded, .failed, .skipped:
            break
        }
    }

    private func wireOffsetCalibrator() {
        offsetCalibrator.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .idle:
                break
            case .requestingPermission:
                self.islandSyncState = .waiting
                self.offsetCalibrationStatusText = L10n.t("offset_cal.requesting")
            case .waitingForLyrics:
                self.islandSyncState = .waiting
                self.offsetCalibrationStatusText = L10n.t("offset_cal.waiting_lyrics")
            case .listening(let progress):
                self.islandSyncState = .listening
                self.offsetCalibrationStatusText = L10n.t(
                    "offset_cal.listening",
                    Int((progress * 100).rounded())
                )
            case .succeeded(let offset, let confidence):
                let completedKey = self.calibratingOffsetKey
                let completedFingerprint = self.calibratingLyricsFingerprint
                let completedRoute = self.calibratingAudioRoute
                self.clearCalibrationCaptureContext()
                if let completedKey, let completedFingerprint, let completedRoute {
                    self.handleCalibrationSample(
                        LyricCalibrationSample(totalOffset: offset, confidence: confidence),
                        for: completedKey,
                        lyricsFingerprint: completedFingerprint,
                        audioRoute: completedRoute
                    )
                }
            case .failed(let message):
                AppDiagnostics.shared.recordCalibration(outcome: "failed")
                self.islandSyncState = .useManual
                let failedKey = self.calibratingOffsetKey
                self.clearCalibrationCaptureContext()
                self.offsetCalibrationStatusText = message
                if let failedKey {
                    self.scheduleCalibrationRetry(offsetKey: failedKey, afterSeconds: 20)
                }
            case .skipped(let message):
                AppDiagnostics.shared.recordCalibration(outcome: "skipped")
                self.islandSyncState = .useManual
                let skippedKey = self.calibratingOffsetKey
                self.clearCalibrationCaptureContext()
                self.offsetCalibrationStatusText = message
                // Quiet / low confidence / intro — try again later on the same track.
                if let skippedKey {
                    self.scheduleCalibrationRetry(offsetKey: skippedKey, afterSeconds: 18)
                }
            }
        }
    }

    private func handleCalibrationSample(
        _ sample: LyricCalibrationSample,
        for offsetKey: String,
        lyricsFingerprint: String,
        audioRoute: String
    ) {
        guard calibrationEvidenceKey == offsetKey,
              calibrationEvidenceLyricsFingerprint == lyricsFingerprint,
              calibrationEvidenceAudioRoute == audioRoute,
              nowPlaying.availability == .ready,
              TrackLyricOffsetStore.trackKey(for: nowPlaying.track) == offsetKey,
              lyrics.timelineFingerprint(duration: nowPlaying.track.duration) == lyricsFingerprint,
              currentAudioCalibrationEnvironment == audioRoute
        else {
            let retryWhenDisabled = calibrationRetryAllowedWhenPreferenceOff
            let currentContext: (fingerprint: String, route: String)? = {
                guard nowPlaying.availability == .ready,
                      TrackLyricOffsetStore.trackKey(for: nowPlaying.track) == offsetKey,
                      lyrics.availability == .synced,
                      nowPlaying.track.isPlaying || playbackClock.isPlaying,
                      let fingerprint = lyrics.timelineFingerprint(
                          duration: nowPlaying.track.duration
                      )
                else { return nil }
                return (fingerprint, currentAudioCalibrationEnvironment)
            }()
            resetCalibrationEvidence()
            if let currentContext,
               preferences.autoCalibrateLyricOffset || retryWhenDisabled
            {
                resetCalibrationEvidence(
                    for: offsetKey,
                    lyricsFingerprint: currentContext.fingerprint,
                    audioRoute: currentContext.route,
                    allowsRetryWhenDisabled: retryWhenDisabled
                )
                islandSyncState = .waiting
                offsetCalibrationStatusText = nil
                pushOverlay()
                scheduleCalibrationRetry(offsetKey: offsetKey, afterSeconds: 1)
            } else {
                islandSyncState = .useManual
                offsetCalibrationStatusText = L10n.t("offset_cal.use_manual")
                pushOverlay()
            }
            return
        }
        let decision = LyricCalibrationPolicy.evaluate(
            previous: pendingCalibrationSample,
            new: sample
        )

        switch decision {
        case .apply(let accepted):
            AppDiagnostics.shared.recordCalibration(
                outcome: "applied",
                confidence: accepted.confidence
            )
            let residual = LyricCalibrationPolicy.trackResidual(
                measuredTotalOffset: accepted.totalOffset,
                globalOffset: preferences.lyricOffsetSeconds
            )
            pendingCalibrationSample = nil
            calibrationSucceededKeys.insert(offsetKey)
            let entry = TrackLyricOffsetEntry(
                offsetSeconds: residual,
                confidence: accepted.confidence,
                source: "auto",
                lyricsFingerprint: lyricsFingerprint,
                audioRoute: audioRoute
            )
            trackOffsetStore.set(entry, forTrackKey: offsetKey)
            if nowPlaying.availability == .ready,
               TrackLyricOffsetStore.trackKey(for: nowPlaying.track) == offsetKey
            {
                applyCurrentTrackOffset(entry)
                islandSyncState = .synced
                pushOverlay()
            }
            offsetCalibrationStatusText = L10n.t(
                "offset_cal.success",
                String(format: "%+.1f", residual),
                Int((accepted.confidence * 100).rounded())
            )

        case .waitForConfirmation(let pending):
            AppDiagnostics.shared.recordCalibration(
                outcome: "confirming",
                confidence: pending.confidence
            )
            pendingCalibrationSample = pending
            islandSyncState = .waiting
            offsetCalibrationStatusText = L10n.t(
                "offset_cal.confirming",
                String(format: "%+.1f", pending.totalOffset),
                Int((pending.confidence * 100).rounded())
            )
            scheduleCalibrationRetry(offsetKey: offsetKey, afterSeconds: 8)

        case .reject:
            AppDiagnostics.shared.recordCalibration(
                outcome: "rejected",
                confidence: sample.confidence
            )
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t(
                "offset_cal.weak_ignored",
                Int((sample.confidence * 100).rounded())
            )
            scheduleCalibrationRetry(offsetKey: offsetKey, afterSeconds: 18)
        }
    }

    private func clearCalibrationCaptureContext() {
        calibratingOffsetKey = nil
        calibratingLyricsFingerprint = nil
        calibratingAudioRoute = nil
    }

    private func scheduleCalibrationRetry(offsetKey: String, afterSeconds: Double) {
        calibrationRetryTask?.cancel()
        let hasAttemptsRemaining = LyricCalibrationPolicy.allowsAnotherAttempt(
            afterStartedAttempts: calibrationAttemptCount
        )
        guard calibrationEvidenceKey == offsetKey, hasAttemptsRemaining else {
            finishCalibrationAttempts(for: offsetKey)
            return
        }
        calibrationRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            let retryIsEnabled = self.preferences.autoCalibrateLyricOffset
                || self.calibrationRetryAllowedWhenPreferenceOff
            guard retryIsEnabled else { return }
            guard self.nowPlaying.availability == .ready else { return }
            let key = TrackLyricOffsetStore.trackKey(for: self.nowPlaying.track)
            guard key == offsetKey else { return }
            guard !self.calibrationSucceededKeys.contains(key) else { return }
            guard LyricCalibrationPolicy.allowsAnotherAttempt(
                afterStartedAttempts: self.calibrationAttemptCount
            ) else {
                self.finishCalibrationAttempts(for: offsetKey)
                return
            }
            let result = self.maybeStartAutoCalibration(
                for: self.nowPlaying.track,
                trackKey: self.trackKey(self.nowPlaying),
                force: true
            )
            self.presentCalibrationStartResult(
                result,
                requestedByUser: self.calibrationRetryAllowedWhenPreferenceOff
            )
        }
    }

    private func finishCalibrationAttempts(for offsetKey: String) {
        calibrationRetryTask?.cancel()
        calibrationRetryTask = nil
        pendingCalibrationSample = nil
        islandSyncState = .useManual
        if trackOffsetStore.offset(forTrackKey: offsetKey) != nil {
            offsetCalibrationStatusText = L10n.t("offset_cal.kept_existing")
        } else {
            offsetCalibrationStatusText = L10n.t("offset_cal.use_manual")
        }
    }

    // MARK: - Overlay / island

    func toggleOverlay() {
        setOverlayVisible(!preferences.isOverlayVisible)
    }

    func setOverlayVisible(_ value: Bool) {
        guard preferences.isOverlayVisible != value else { return }
        preferences.isOverlayVisible = value
        persist()
        pushOverlay()
    }

    func togglePreferExpanded() {
        setPreferExpanded(!preferences.preferExpanded)
    }

    /// Explicit setter so SwiftUI `Toggle` cannot flip state via a bare `toggle()` binding.
    func setPreferExpanded(_ value: Bool) {
        guard preferences.preferExpanded != value else { return }
        preferences.preferExpanded = value
        // Clear transient so lock state is obvious.
        if value {
            transientExpandUntil = nil
            transientExpandTask?.cancel()
        }
        persist()
        pushOverlay()
    }

    func toggleExpandOnTrackChange() {
        setExpandOnTrackChange(!preferences.expandOnTrackChange)
    }

    func setExpandOnTrackChange(_ value: Bool) {
        guard preferences.expandOnTrackChange != value else { return }
        preferences.expandOnTrackChange = value
        persist()
    }

    /// Pulse expand / collapse for the island. Does **not** clear 「維持展開」—
    /// only `setPreferExpanded` / the dedicated toggle may change that lock.
    ///
    /// ✕ / hotkey while open → force collapse even if the cursor is still over the island.
    func toggleExpand() {
        if preferences.preferExpanded {
            return
        }
        if effectiveIslandMode == .expanded {
            collapseIslandFromUser()
            return
        }
        pulseExpand(seconds: 4.0)
    }

    /// Menu actions describe the result (expand/collapse), so an explicit collapse
    /// also releases the persistent expanded lock instead of appearing unresponsive.
    func toggleExpandFromMenu() {
        if preferences.preferExpanded {
            setPreferExpanded(false)
            collapseIslandFromUser()
            return
        }
        toggleExpand()
    }

    /// User-initiated collapse (✕ button or hotkey). Stays collapsed until the
    /// pointer leaves the hit area, so hover does not immediately re-open.
    func collapseIslandFromUser() {
        if preferences.preferExpanded { return }
        suppressHoverExpand = true
        isHoveringIsland = false
        transientExpandUntil = nil
        transientExpandTask?.cancel()
        pushOverlay()
    }

    /// Called by the overlay mouse monitor: pointer over notch/card ↔ expand.
    func setIslandPointerInside(_ inside: Bool) {
        var changed = false

        if inside {
            // After ✕, ignore “still inside” until the pointer has left once.
            if suppressHoverExpand {
                return
            }
            if !isHoveringIsland {
                isHoveringIsland = true
                changed = true
            }
        } else {
            // Left the island — allow hover-expand again on next entry.
            if suppressHoverExpand {
                suppressHoverExpand = false
                changed = true
            }
            if isHoveringIsland {
                isHoveringIsland = false
                changed = true
            }
            if transientExpandUntil != nil {
                transientExpandUntil = nil
                transientExpandTask?.cancel()
                changed = true
            }
        }

        if changed {
            // Dynamic Island–style spring (smooth overshoot, reference-app silkiness).
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)) {
                pushOverlay()
            }
        }
    }

    func toggleClickThrough() {
        setClickThrough(!preferences.appearance.clickThrough)
    }

    func setClickThrough(_ value: Bool) {
        guard preferences.appearance.clickThrough != value else { return }
        mutateAppearance { $0.clickThrough = value }
        if value {
            isHoveringIsland = false
        }
    }

    func toggleAdjacentLines() {
        setShowAdjacentLines(!preferences.appearance.showAdjacentLines)
    }

    func setShowAdjacentLines(_ value: Bool) {
        guard preferences.appearance.showAdjacentLines != value else { return }
        mutateAppearance { $0.showAdjacentLines = value }
    }

    func toggleShowTrackTitle() {
        setShowTrackTitle(!preferences.appearance.showTrackTitle)
    }

    func setShowTrackTitle(_ value: Bool) {
        guard preferences.appearance.showTrackTitle != value else { return }
        mutateAppearance { $0.showTrackTitle = value }
    }

    func setLiquidGlassOnNotch(_ enabled: Bool) {
        mutateAppearance { $0.liquidGlassOnNotch = enabled }
    }

    func setLiquidGlassOnFloating(_ enabled: Bool) {
        mutateAppearance { $0.liquidGlassOnFloating = enabled }
    }

    func setGlassVariant(_ variant: LiquidGlassVariant) {
        mutateAppearance { $0.glassVariant = variant }
    }

    func setOpacity(_ value: Double) {
        mutateAppearance { $0.opacity = value }
    }

    func setFontSize(_ value: Double) {
        mutateAppearance { $0.fontSize = value }
    }

    func setScreenPlacement(_ placement: ScreenPlacement) {
        preferences.screenPlacement = placement
        persist()
        applyOverlayPreferences()
        pushOverlay()
    }

    func setVerticalOffset(_ value: Double) {
        preferences.verticalOffset = value
        persist()
        applyOverlayPreferences()
        pushOverlay()
    }

    func resetOverlayLayout() {
        guard abs(preferences.verticalOffset) > 0.01
                || abs(preferences.islandExtraWidth) > 0.01
        else { return }

        preferences.verticalOffset = 0
        preferences.islandExtraWidth = 0
        persist()
        applyOverlayPreferences()
        pushOverlay()
    }

    func toggleHotKey() {
        setHotKeyEnabled(!preferences.hotKeyEnabled)
    }

    func setHotKeyEnabled(_ enabled: Bool) {
        guard preferences.hotKeyEnabled != enabled else { return }
        preferences.hotKeyEnabled = enabled
        persist()
        configureHotKey()
    }

    func toggleLaunchAtLogin() {
        setLaunchAtLoginEnabled(!LaunchAtLogin.isEnabled)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        let actual = LaunchAtLogin.isEnabled
        if actual == enabled {
            if preferences.launchAtLogin != enabled {
                preferences.launchAtLogin = enabled
                persist()
            }
            refreshLaunchAtLoginStatus()
            return
        }

        let result = LaunchAtLogin.setEnabled(enabled)
        switch result {
        case .success:
            preferences.launchAtLogin = LaunchAtLogin.isEnabled
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
            preferences.launchAtLogin = LaunchAtLogin.isEnabled
        }
        persist()
        refreshLaunchAtLoginStatus()
    }

    func refreshNow() {
        Task {
            await self.tick(forceLyrics: true)
        }
    }

    func clearStoredLyricsAndOffsets() {
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        translationTask?.cancel()
        translationTask = nil
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        calibrationRetryTask = nil
        clearCalibrationCaptureContext()
        resetCalibrationEvidence()
        calibrationSucceededKeys.removeAll()
        tapSyncStore.clearAll()
        clearTapSyncSession()
        let operationID = beginManualTimelineOperation()
        forcedCalibrationAfterLyricsFetchKey = nil
        islandSyncState = .none
        offsetCalibrationStatusText = nil
        trackOffsetStore.clearAll()
        applyCurrentTrackOffset(nil)
        lyrics = .skipped
        lyricsSearch.stop()
        currentTranslation = nil
        lastTranslatedSource = nil
        pushOverlay()
        let lyricsService = self.lyricsService
        let artworkService = self.artworkService
        manualTimelineMutationQueue.enqueue { [weak self] in
            await lyricsService.clearStoredLyrics()
            await artworkService.clearCache()
            await TranslationService.shared.clearCache()
            guard let self,
                  self.manualTimelineRequestID == operationID
            else { return }
            await self.tick(forceLyrics: true)
        }
    }

    func quit() {
        stop()
        NSApp.terminate(nil)
    }

    // MARK: - Poll

    func tick(forceLyrics: Bool = false) async {
        tickRequestID &+= 1
        let requestID = tickRequestID
        let previousReadyKey = nowPlaying.availability == .ready ? trackKey(nowPlaying) : nil
        let wasPlaying = nowPlaying.availability == .ready && nowPlaying.track.isPlaying
        let fetchedSnapshot = await loadNowPlayingSnapshot()
        guard requestID == tickRequestID, !Task.isCancelled else { return }
        let snap: NowPlayingSnapshot
        if fetchedSnapshot.availability == .ready {
            consecutiveNowPlayingErrors = 0
            playbackWarning = nil
            if applyReadyNowPlayingSnapshot(fetchedSnapshot) {
                snap = fetchedSnapshot
            } else {
                // A concurrent lyrics refresh may have already supplied a newer
                // sample for this track. Continue this tick from the applied one.
                snap = nowPlaying
            }
        } else if fetchedSnapshot.availability == .error,
                  nowPlaying.availability == .ready,
                  consecutiveNowPlayingErrors < 2
        {
            // A single AppleScript timeout/permission hiccup must not erase the
            // current lyrics, artwork, and overlay. Degrade only after three
            // consecutive failures.
            consecutiveNowPlayingErrors += 1
            playbackWarning = fetchedSnapshot.detail
            snap = nowPlaying
        } else {
            if fetchedSnapshot.availability == .error {
                consecutiveNowPlayingErrors += 1
                playbackWarning = fetchedSnapshot.detail
            } else {
                consecutiveNowPlayingErrors = 0
                playbackWarning = nil
            }
            nowPlaying = fetchedSnapshot
            playbackClock = PlaybackClock()
            snap = fetchedSnapshot
        }
        await lyricsService.setPlayerSource(snap.source)
        guard requestID == tickRequestID, !Task.isCancelled else { return }
        if snap.availability == .ready {
            invalidateAutomaticOffsetIfAudioRouteChanged(for: snap.track)
        }

        let key = trackKey(snap)
        if forceLyrics || key != lastTrackKey {
            let previous = lastTrackKey
            lastTrackKey = key
            lyricsSearch.trackDidChange(
                to: snap.availability == .ready ? snap.track : nil,
                trackKey: snap.availability == .ready ? key : nil
            )
            currentTranslation = nil
            lastTranslatedSource = nil
            if previous != key {
                lyricsTimelineOperationStatusText = nil
                beginManualTimelineOperation()
                if tapSyncProject != nil {
                    clearTapSyncSession(status: L10n.t("tap_sync.track_changed"))
                }
                stopOffsetCalibrationIfActive()
                calibrationRetryTask?.cancel()
                clearCalibrationCaptureContext()
                forcedCalibrationAfterLyricsFetchKey = nil
                resetCalibrationEvidence()
                islandSyncState = .none
                // The track ID alone is insufficient to validate an offset. Wait
                // until this track's exact lyric timeline has been loaded.
                applyCurrentTrackOffset(nil)
                artworkImage = nil
                artworkTrackKey = nil
                artworkRetryAfter = nil
            }
            if snap.availability == .ready {
                if forceLyrics {
                    await lyricsService.clearCache()
                    artworkTrackKey = nil
                    artworkRetryAfter = nil
                }
                // Clear stale lines + show loading while fetch runs.
                if previous != key {
                    lyrics = LyricsSnapshot(availability: .skipped, detail: "loading")
                }
                if previous != nil, previous != key, preferences.expandOnTrackChange {
                    pulseExpand(seconds: 2.4)
                }
                // Fetch off the poll loop so position sampling + clock keep moving.
                startLyricsFetch(for: snap.track, trackKey: key, alsoArtwork: true)
            } else {
                lyricsFetchTask?.cancel()
                lyricsFetchTask = nil
                lyrics = .skipped
                isFetchingLyrics = false
                transientExpandUntil = nil
                artworkImage = nil
                artworkTrackKey = nil
                artworkRetryAfter = nil
                applyCurrentTrackOffset(nil)
            }
        } else if snap.availability == .ready, artworkImage == nil {
            await refreshArtwork(for: snap)
        }

        // A lyrics fetch or retry may have landed while the player was paused.
        // Resume is a new opportunity; otherwise same-key polls never revisit
        // automatic calibration for the rest of the track.
        if snap.availability == .ready,
           snap.track.isPlaying,
           !wasPlaying,
           previousReadyKey == key
        {
            let offsetKey = TrackLyricOffsetStore.trackKey(for: snap.track)
            let resumeUserRequestedCalibration = calibrationEvidenceKey == offsetKey
                && calibrationRetryAllowedWhenPreferenceOff
            let result = maybeStartAutoCalibration(
                for: snap.track,
                trackKey: key,
                force: resumeUserRequestedCalibration
            )
            presentCalibrationStartResult(
                result,
                requestedByUser: resumeUserRequestedCalibration
            )
        }

        pushOverlay()
        refreshTranslationIfNeeded()
    }

    /// Background lyrics fetch. Does **not** block the poll loop / playback clock.
    @discardableResult
    func startLyricsFetch(
        for track: Track,
        trackKey key: String,
        alsoArtwork: Bool
    ) -> Task<Void, Never> {
        lyricsFetchTask?.cancel()
        isFetchingLyrics = true
        pushOverlay()

        let task = Task { [weak self] in
            guard let self else { return }
            let result = await self.loadLyricsSnapshot(for: track)
            guard self.isCurrentLyricsRequest(key) else { return }

            let previousFingerprint = self.lyrics.timelineFingerprint(duration: track.duration)
            let nextFingerprint = result.timelineFingerprint(duration: track.duration)
            if previousFingerprint != nextFingerprint {
                self.stopOffsetCalibrationIfActive()
                self.calibrationRetryTask?.cancel()
                self.clearCalibrationCaptureContext()
                self.resetCalibrationEvidence()
                self.calibrationSucceededKeys.remove(
                    TrackLyricOffsetStore.trackKey(for: track)
                )
            }
            self.lyrics = result
            self.isFetchingLyrics = false
            _ = self.reloadTrackAutoOffset(for: track)
            // Publish the completed lyrics immediately. A fresh player sample or
            // artwork request may be slow, and paused tracks have no 20 Hz display
            // tick to clear the loading state on their behalf.
            self.pushOverlay()
            self.refreshTranslationIfNeeded()

            // Re-sample player position so the first painted line matches “now”,
            // not the (possibly multi-second-old) position from when fetch started.
            let fresh = await self.loadNowPlayingSnapshot()
            guard self.isCurrentLyricsRequest(key) else { return }
            guard fresh.availability == .ready else {
                self.finishForcedCalibrationFetch(
                    for: key,
                    blockedBy: .playbackUnavailable
                )
                return
            }
            guard self.trackKey(fresh) == key else {
                self.clearForcedCalibrationFetch(for: key)
                return
            }
            // The extra query can start first yet finish after the regular poll
            // because each query waits for both players. Never let that older
            // same-track position replace the newer poll sample.
            _ = self.applyReadyNowPlayingSnapshot(fresh)

            self.pushOverlay()
            self.refreshTranslationIfNeeded()
            let forceCalibration = self.forcedCalibrationAfterLyricsFetchKey == key
            if forceCalibration {
                self.forcedCalibrationAfterLyricsFetchKey = nil
            }
            // Do not let an unrelated artwork download postpone timeline
            // calibration; it can continue while the microphone pass runs.
            let calibrationResult = self.maybeStartAutoCalibration(
                for: self.nowPlaying.track,
                trackKey: key,
                force: forceCalibration
            )
            self.presentCalibrationStartResult(
                calibrationResult,
                requestedByUser: forceCalibration
            )

            if alsoArtwork {
                await self.refreshArtwork(for: self.nowPlaying)
                guard self.isCurrentLyricsRequest(key) else { return }
            }
            self.pushOverlay()
            self.refreshTranslationIfNeeded()
        }
        lyricsFetchTask = task
        return task
    }

    private func isCurrentLyricsRequest(_ key: String) -> Bool {
        !Task.isCancelled
            && lastTrackKey == key
            && trackKey(nowPlaying) == key
    }

    private func loadLyricsSnapshot(for track: Track) async -> LyricsSnapshot {
        let startedAt = Date()
        let fetched: LyricsSnapshot
        if let lyricsSnapshotOverride {
            fetched = await lyricsSnapshotOverride(track)
        } else {
            fetched = await lyricsService.snapshot(for: track)
        }
        let snapshot: LyricsSnapshot
        if let project = tapSyncStore.project(
            for: track,
            source: track.source,
            matching: fetched
        ), !project.anchors.isEmpty,
           let resolved = try? project.syncedSnapshot()
        {
            snapshot = resolved
        } else {
            snapshot = fetched
        }
        AppDiagnostics.shared.recordLyrics(
            availability: snapshot.availability,
            source: snapshot.source,
            lineCount: snapshot.lines.count,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        return snapshot
    }

    private func loadNowPlayingSnapshot() async -> NowPlayingSnapshot {
        let startedAt = Date()
        let snapshot: NowPlayingSnapshot
        if let nowPlayingSnapshotOverride {
            snapshot = await nowPlayingSnapshotOverride()
        } else {
            snapshot = await nowPlayingService.snapshot(
                preferredSource: preferences.playerSelectionPreference.preferredSource
            )
        }
        AppDiagnostics.shared.recordPlayback(
            availability: snapshot.availability,
            source: snapshot.source,
            latencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        return snapshot
    }

    /// Applies a ready snapshot only when its same-track position sample is not
    /// older than the one already shown. `PlaybackClock` performs a second check
    /// against optimistic seeks and other clock-only updates.
    @discardableResult
    private func applyReadyNowPlayingSnapshot(_ snapshot: NowPlayingSnapshot) -> Bool {
        guard snapshot.availability == .ready else { return false }
        if nowPlaying.availability == .ready,
           trackKey(snapshot) == trackKey(nowPlaying),
           isOlderPositionSample(snapshot.track, than: nowPlaying.track)
        {
            return false
        }
        guard playbackClock.sample(from: snapshot.track) else { return false }
        nowPlaying = snapshot
        return true
    }

    private func isOlderPositionSample(_ candidate: Track, than current: Track) -> Bool {
        guard let currentDate = current.positionSampledAt else { return false }
        guard let candidateDate = candidate.positionSampledAt else { return true }
        return candidateDate < currentDate
    }

    private func finishForcedCalibrationFetch(
        for key: String,
        blockedBy reason: AutoCalibrationBlockReason
    ) {
        guard forcedCalibrationAfterLyricsFetchKey == key else { return }
        forcedCalibrationAfterLyricsFetchKey = nil
        presentCalibrationStartResult(.blocked(reason), requestedByUser: true)
        pushOverlay()
    }

    private func clearForcedCalibrationFetch(for key: String) {
        guard forcedCalibrationAfterLyricsFetchKey == key else { return }
        forcedCalibrationAfterLyricsFetchKey = nil
        offsetCalibrationStatusText = nil
        islandSyncState = .none
        pushOverlay()
    }

    /// Speaker-only mic calibration with bounded retries and confirmation for noisy results.
    private func maybeStartAutoCalibration(
        for track: Track,
        trackKey _: String,
        force: Bool
    ) -> AutoCalibrationStartResult {
        guard preferences.autoCalibrateLyricOffset || force else { return .noAction }
        guard track.isPlaying || playbackClock.isPlaying else {
            return .blocked(.paused)
        }
        guard lyrics.source != TapSyncProject.outputSource else {
            return force ? .blocked(.manuallyTimedTimeline) : .noAction
        }
        guard lyrics.availability == .synced else {
            return .blocked(.noTimedLyrics)
        }

        let offsetKey = TrackLyricOffsetStore.trackKey(for: track)
        let lyricTimes = usableTimedLyricTimes
        guard let lyricsFingerprint = lyrics.timelineFingerprint(duration: track.duration) else {
            return .blocked(.tooFewTimedLines(lyricTimes.count))
        }
        let audioRoute = currentAudioCalibrationEnvironment
        if calibrationEvidenceKey != offsetKey
            || calibrationEvidenceLyricsFingerprint != lyricsFingerprint
            || calibrationEvidenceAudioRoute != audioRoute
        {
            let preserveUserRequestedRetries = calibrationEvidenceKey == offsetKey
                && calibrationRetryAllowedWhenPreferenceOff
            resetCalibrationEvidence(
                for: offsetKey,
                lyricsFingerprint: lyricsFingerprint,
                audioRoute: audioRoute,
                allowsRetryWhenDisabled: preserveUserRequestedRetries
            )
        }

        // A trusted saved value wins unless the user explicitly requests recalibration.
        if !force, let existing = trackOffsetStore.offset(forTrackKey: offsetKey) {
            if LyricCalibrationPolicy.acceptsStoredOffset(
                existing,
                lyricsFingerprint: lyricsFingerprint,
                audioRoute: audioRoute
            ) {
                applyCurrentTrackOffset(existing)
                if existing.source == "auto" {
                    calibrationSucceededKeys.insert(offsetKey)
                }
                return .noAction
            }
            trackOffsetStore.remove(forTrackKey: offsetKey)
            calibrationSucceededKeys.remove(offsetKey)
            applyCurrentTrackOffset(nil)
            islandSyncState = .none
        }
        if !force, calibrationSucceededKeys.contains(offsetKey) { return .noAction }

        switch offsetCalibrator.state {
        case .listening, .waitingForLyrics, .requestingPermission:
            return force ? .blocked(.calibratorBusy) : .noAction
        default:
            break
        }

        guard lyricTimes.count >= 3 else {
            return .blocked(.tooFewTimedLines(lyricTimes.count))
        }

        // Headphones / BT: skip mic; island chips still work for manual nudge.
        let micCalibrationLikelyUseful = micCalibrationLikelyUsefulOverride?()
            ?? AudioOutputProbe.micCalibrationLikelyUseful
        guard micCalibrationLikelyUseful else {
            return .blocked(.headphones)
        }

        guard LyricCalibrationPolicy.allowsAnotherAttempt(
            afterStartedAttempts: calibrationAttemptCount
        ) else {
            finishCalibrationAttempts(for: offsetKey)
            return .noAction
        }

        calibratingOffsetKey = offsetKey
        calibratingLyricsFingerprint = lyricsFingerprint
        calibratingAudioRoute = audioRoute
        calibrationAttemptCount += 1
        offsetCalibrator.start(
            lyricTimes: lyricTimes,
            position: { [weak self] in self?.playbackClock.position() ?? 0 },
            isPlaying: { [weak self] in
                guard let self else { return false }
                return self.playbackClock.isPlaying
            },
            // Slow songs often have fewer than three lyric onsets in 14 seconds.
            // Use the calibrator's bounded maximum so those tracks can qualify.
            duration: 18,
            currentTotalOffset: effectiveLyricOffset
        )
        return .started
    }

    private func presentCalibrationStartResult(
        _ result: AutoCalibrationStartResult,
        requestedByUser: Bool
    ) {
        switch result {
        case .started, .noAction:
            break
        case .blocked(.headphones):
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_headphones")
        case .blocked(.paused) where requestedByUser:
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_paused")
        case .blocked(.noTimedLyrics) where requestedByUser:
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t("offset_cal.no_timed_lyrics")
        case .blocked(.tooFewTimedLines(let count)) where requestedByUser:
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t("offset_cal.too_few_timed_lines", count)
        case .blocked(.manuallyTimedTimeline) where requestedByUser:
            islandSyncState = .synced
            offsetCalibrationStatusText = L10n.t("offset_cal.manual_timeline")
        case .blocked(.calibratorBusy) where requestedByUser:
            islandSyncState = .waiting
        case .blocked(.playbackUnavailable) where requestedByUser:
            islandSyncState = .useManual
            offsetCalibrationStatusText = L10n.t("offset_cal.need_playing")
        case .blocked:
            break
        }
    }

    private func resetCalibrationEvidence(
        for offsetKey: String? = nil,
        lyricsFingerprint: String? = nil,
        audioRoute: String? = nil,
        allowsRetryWhenDisabled: Bool = false
    ) {
        calibrationEvidenceKey = offsetKey
        calibrationEvidenceLyricsFingerprint = lyricsFingerprint
        calibrationEvidenceAudioRoute = audioRoute
        calibrationAttemptCount = 0
        pendingCalibrationSample = nil
        calibrationRetryAllowedWhenPreferenceOff = allowsRetryWhenDisabled
    }

    private func refreshArtwork(for snap: NowPlayingSnapshot) async {
        guard snap.availability == .ready else {
            artworkImage = nil
            artworkTrackKey = nil
            artworkRetryAfter = nil
            return
        }
        let key = trackKey(snap)
        if key == artworkTrackKey {
            if artworkImage != nil { return }
            if let artworkRetryAfter, artworkRetryAfter > Date() { return }
        }
        artworkTrackKey = key
        artworkRetryAfter = nil
        let image: NSImage?
        if let artworkImageOverride {
            image = await artworkImageOverride(snap.track, snap.source)
        } else {
            image = await artworkService.image(for: snap.track, source: snap.source)
        }
        guard !Task.isCancelled,
              artworkTrackKey == key,
              lastTrackKey == key,
              trackKey(nowPlaying) == key
        else { return }
        // Always assign + push so the wing art appears as soon as the download finishes
        // (even if a concurrent poll already pushed a nil-art frame).
        artworkImage = image
        artworkRetryAfter = image == nil ? Date().addingTimeInterval(60) : nil
        pushOverlay()
    }

    private func pulseExpand(seconds: TimeInterval) {
        guard !preferences.preferExpanded else {
            pushOverlay()
            return
        }
        transientExpandUntil = Date().addingTimeInterval(seconds)
        transientExpandTask?.cancel()
        transientExpandTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.transientExpandUntil = nil
            self.pushOverlay()
        }
        pushOverlay()
    }

    private func wireOverlayCallbacks() {
        overlay.onToggleExpand = { [weak self] in
            self?.toggleExpand()
        }
        overlay.onHoverChanged = { [weak self] hovering in
            self?.setIslandPointerInside(hovering)
        }
        overlay.onPlayPause = { [weak self] in
            Task { @MainActor [weak self] in await self?.runPlayback(.playPause) }
        }
        overlay.onNext = { [weak self] in
            Task { @MainActor [weak self] in await self?.runPlayback(.next) }
        }
        overlay.onPrevious = { [weak self] in
            Task { @MainActor [weak self] in await self?.runPlayback(.previous) }
        }
        overlay.onSeek = { [weak self] seconds in
            Task { @MainActor [weak self] in await self?.runSeek(to: seconds) }
        }
        overlay.onRefreshLyrics = { [weak self] in
            self?.refreshNow()
        }
        overlay.onNudgeTrackOffset = { [weak self] delta in
            self?.nudgeTrackAutoOffset(by: delta)
        }
        overlay.onResetTrackOffset = { [weak self] in
            self?.clearCurrentTrackAutoOffset()
        }
    }

    private func runPlayback(_ command: PlaybackService.Command) async {
        let source = nowPlaying.source ?? .spotify
        do {
            try await playbackService.perform(command, source: source)
            lastError = nil
            // Refresh soon so play/pause glyph and track updates feel instant.
            try? await Task.sleep(for: .milliseconds(120))
            await tick(forceLyrics: command != .playPause)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func runSeek(to seconds: TimeInterval) async {
        let source = nowPlaying.source ?? .spotify
        do {
            try await playbackService.seek(to: seconds, source: source)
            lastError = nil
            // Optimistic UI update before next poll.
            if nowPlaying.availability == .ready {
                nowPlaying.track.position = max(0, seconds)
                playbackClock.seek(to: seconds)
            }
            try? await Task.sleep(for: .milliseconds(80))
            await tick(forceLyrics: false)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pushOverlay() {
        guard rendersOverlay else { return }
        let rawStatus = statusMessage(for: nowPlaying, lyrics: lyrics)
        // Interpolated playhead + global + saved track + session calibration.
        let rawPosition = playbackClock.position()
        let position = max(0, rawPosition + effectiveLyricOffset)
        let track: Track
        switch nowPlaying.availability {
        case .ready:
            // Surface live estimated position on the track model (progress bar / time).
            var live = nowPlaying.track
            live.position = rawPosition
            track = live
        case .playerNotRunning, .noTrack, .error:
            track = .empty
        }
        // Prefer real LRC; for plain-only tracks estimate a timeline so the island shows words.
        let displayLines = displayLinesForOverlay(duration: track.duration)
        var status: String? = rawStatus
        if isFetchingLyrics {
            status = L10n.t("status.loading_lyrics")
        }
        if preferences.displayTraditionalChinese {
            if let s = status {
                status = TrackQueryNormalizer.traditionalChinese(s)
            }
        }
        let accent: Color? = preferences.lyricColorFromArtwork ? artworkAccent : nil

        var translation = currentTranslation
        if translation != nil,
           lastTranslatedSource != activeRawLyricSource(
                position: position,
                duration: track.duration
           )
        {
            translation = nil
        }
        if preferences.displayTraditionalChinese, let t = translation {
            translation = TrackQueryNormalizer.traditionalChinese(t)
        }

        overlay.update(
            track: track,
            lines: displayLines,
            position: position,
            lyricsAvailability: lyrics.availability,
            statusMessage: status,
            islandMode: effectiveIslandMode,
            expandLocked: preferences.preferExpanded,
            playerSource: nowPlaying.source,
            artwork: artworkImage,
            lyricAccent: accent,
            translationText: preferences.showTranslation ? translation : nil,
            isLoadingLyrics: isFetchingLyrics,
            syncStatusText: islandSyncSummaryText,
            trackOffsetSeconds: trackLyricOffsetSeconds,
            hasTrackOffset: currentTrackOffsetSource != nil
        )
        overlay.setVisible(shouldPresentOverlay)
    }

    private func rawDisplayLines(duration: TimeInterval?) -> [LyricLine] {
        lyricsDisplayCache.raw(snapshot: lyrics, duration: duration)
    }

    private func displayLinesForOverlay(duration: TimeInterval?) -> [LyricLine] {
        lyricsDisplayCache.display(
            snapshot: lyrics,
            duration: duration,
            traditional: preferences.displayTraditionalChinese
        )
    }

    // MARK: - Translation

    private func activeRawLyricSource(
        position: TimeInterval,
        duration: TimeInterval?
    ) -> String? {
        let lines = rawDisplayLines(duration: duration)
        guard let index = LyricLine.activeIndex(in: lines, at: position),
              lines.indices.contains(index)
        else { return nil }
        let source = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? nil : source
    }

    private func refreshTranslationIfNeeded() {
        guard preferences.showTranslation else {
            cancelTranslationWork()
            return
        }
        guard nowPlaying.availability == .ready else {
            cancelTranslationWork()
            return
        }
        let pos = max(0, playbackClock.position() + effectiveLyricOffset)
        let lines = rawDisplayLines(duration: nowPlaying.track.duration)
        guard let idx = LyricLine.activeIndex(in: lines, at: pos),
              lines.indices.contains(idx)
        else {
            cancelTranslationWork()
            return
        }
        let source = lines[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            cancelTranslationWork()
            return
        }
        let nextSource = lines.dropFirst(idx + 1)
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0 != source })
        if source == lastTranslatedSource { return }
        lastTranslatedSource = source
        translationTask?.cancel()
        // Never present the previous line's translation under a new source line
        // while the network request is in flight.
        currentTranslation = nil
        pushOverlay()
        translationTask = Task { [weak self] in
            guard let self else { return }
            let target = self.preferences.translationTargetLanguage
            let text = await TranslationService.shared.translate(source, to: target)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.lastTranslatedSource == source,
                      self.preferences.translationTargetLanguage == target
                else { return }
                self.currentTranslation = text
                self.pushOverlay()
            }
            // Warm the bounded TranslationService cache for the next lyric line.
            // Cancellation on a fast line change immediately yields to the new
            // current-line request.
            if let nextSource,
               !Task.isCancelled,
               self.preferences.showTranslation,
               self.preferences.translationTargetLanguage == target,
               self.lastTranslatedSource == source
            {
                _ = await TranslationService.shared.translate(nextSource, to: target)
            }
        }
    }

    private func cancelTranslationWork() {
        translationTask?.cancel()
        translationTask = nil
        currentTranslation = nil
        lastTranslatedSource = nil
    }

    func setShowTranslation(_ value: Bool) {
        guard preferences.showTranslation != value else { return }
        preferences.showTranslation = value
        persist()
        if !value { cancelTranslationWork() }
        pushOverlay()
        refreshTranslationIfNeeded()
    }

    func setTranslationTargetLanguage(_ code: String) {
        guard preferences.translationTargetLanguage != code else { return }
        preferences.translationTargetLanguage = code
        lastTranslatedSource = nil
        currentTranslation = nil
        persist()
        refreshTranslationIfNeeded()
    }

    func setLyricsSourcePreference(_ pref: LyricsSourcePreference) {
        guard preferences.lyricsSourcePreference != pref else { return }
        preferences.lyricsSourcePreference = pref
        persist()
        Task {
            await lyricsService.setPreference(pref)
            await lyricsService.clearCache()
            await tick(forceLyrics: true)
        }
    }

    func setPlayerSelectionPreference(_ preference: PlayerSelectionPreference) {
        guard preferences.playerSelectionPreference != preference else { return }
        preferences.playerSelectionPreference = preference
        persist()
        Task { await tick(forceLyrics: false) }
    }

    // MARK: - Local LRC import

    func importLocalLRC(from fileURL: URL) {
        guard nowPlaying.availability == .ready else {
            lyricsTimelineOperationStatusText = L10n.t("lrc_import.no_track")
            return
        }
        guard !isImportingLocalLRC else { return }

        let track = nowPlaying.track
        let source = nowPlaying.source
        let expectedTrackKey = trackKey(nowPlaying)
        let importer = localLRCImporter
        let importOverride = localLRCImportOverride
        let operationID = beginManualTimelineOperation()
        isImportingLocalLRC = true
        lyricsTimelineOperationStatusText = L10n.t("lrc_import.reading")

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.manualTimelineRequestID == operationID {
                    self.isImportingLocalLRC = false
                    self.localLRCImportTask = nil
                }
            }
            do {
                let imported: LocalLRCImportResult
                if let importOverride {
                    imported = try await importOverride(fileURL)
                } else {
                    imported = try await Task.detached(priority: .userInitiated) {
                        try importer.load(from: fileURL)
                    }.value
                }
                try Task.checkCancellation()
                guard self.manualTimelineRequestID == operationID else { return }
                guard self.nowPlaying.availability == .ready,
                      self.trackKey(self.nowPlaying) == expectedTrackKey
                else {
                    self.lyricsTimelineOperationStatusText = L10n.t(
                        "lrc_import.track_changed"
                    )
                    return
                }

                // A same-track provider fetch is validated only by track key.
                // Stop it before pinning the local file so it cannot overwrite
                // the explicit selection when its network response arrives.
                self.lyricsFetchTask?.cancel()
                self.lyricsFetchTask = nil
                self.isFetchingLyrics = false
                self.forcedCalibrationAfterLyricsFetchKey = nil

                let lyricsService = self.lyricsService
                let persistence = self.manualTimelineMutationQueue.enqueue { [weak self] in
                    guard let self,
                          self.manualTimelineRequestID == operationID,
                          self.nowPlaying.availability == .ready,
                          self.trackKey(self.nowPlaying) == expectedTrackKey
                    else { return }
                    let applied = await lyricsService.apply(
                        importedLRC: imported,
                        to: track,
                        source: source
                    )
                    guard self.manualTimelineRequestID == operationID else { return }
                    guard self.nowPlaying.availability == .ready,
                          self.trackKey(self.nowPlaying) == expectedTrackKey
                    else {
                        self.lyricsTimelineOperationStatusText = L10n.t(
                            "lrc_import.track_changed"
                        )
                        return
                    }

                    self.tapSyncStore.remove(for: track, source: source)
                    self.clearTapSyncSession()
                    self.replaceCurrentLyricsTimeline(with: applied, for: track)
                    self.lyricsTimelineOperationStatusText = L10n.t(
                        "lrc_import.success",
                        imported.metadata.originalFileName,
                        imported.metadata.usableTimedLineCount
                    )
                }
                await persistence.value
            } catch is CancellationError {
                return
            } catch let error as LocalLRCImportError {
                guard self.manualTimelineRequestID == operationID else { return }
                self.lyricsTimelineOperationStatusText = self.localLRCImportMessage(
                    for: error
                )
            } catch {
                guard self.manualTimelineRequestID == operationID else { return }
                self.lyricsTimelineOperationStatusText = L10n.t("lrc_import.unreadable")
            }
        }
        localLRCImportTask = task
    }

    func reportLocalLRCSelectionError(_ error: Error) {
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .userCancelled
        {
            return
        }
        lyricsTimelineOperationStatusText = L10n.t("lrc_import.picker_failed")
    }

    private func localLRCImportMessage(for error: LocalLRCImportError) -> String {
        switch error {
        case .unsupportedFileExtension:
            return L10n.t("lrc_import.wrong_extension")
        case .fileTooLarge:
            return L10n.t("lrc_import.too_large")
        case .unsupportedEncoding:
            return L10n.t("lrc_import.unsupported_encoding")
        case .noTimedLyrics, .noUsableTimedLyrics:
            return L10n.t("lrc_import.no_timed_lyrics")
        case .notFileURL, .notRegularFile, .unreadableFile:
            return L10n.t("lrc_import.unreadable")
        case .emptyFile, .invalidTextContent, .tooManySourceLines,
             .lineTooLong, .tooManyTimedLines:
            return L10n.t("lrc_import.invalid")
        }
    }

    private func cancelLocalLRCImport() {
        localLRCImportTask?.cancel()
        localLRCImportTask = nil
        isImportingLocalLRC = false
    }

    /// Starts a mutually exclusive manual-timeline mutation. Canceling first
    /// keeps a superseded local-file task from leaving the import UI busy or
    /// publishing an error over a newer Tap Sync/search action.
    @discardableResult
    private func beginManualTimelineOperation() -> Int {
        cancelLocalLRCImport()
        manualTimelineRequestID &+= 1
        return manualTimelineRequestID
    }

    /// Internal completion barrier used by deterministic integration tests.
    func waitForManualTimelinePersistence() async {
        await manualTimelineMutationQueue.waitForIdle()
    }

    private func enqueueManualLyricsPersistence(
        _ snapshot: LyricsSnapshot?,
        for track: Track,
        source: MusicPlayerSource?
    ) {
        let lyricsService = self.lyricsService
        manualTimelineMutationQueue.enqueue {
            if let snapshot {
                _ = await lyricsService.apply(
                    manualSnapshot: snapshot,
                    to: track,
                    source: source
                )
            } else {
                await lyricsService.removePinnedLyrics(for: track, source: source)
            }
        }
    }

    /// Persists the latest editable revision after every anchor mutation. This
    /// is both autosave and the corrective write that prevents an older queued
    /// save from winning after Undo or another edit.
    private func enqueueTapSyncPersistence(
        _ project: TapSyncProject,
        for track: Track,
        source: MusicPlayerSource?
    ) {
        if !project.anchors.isEmpty,
           let snapshot = try? project.syncedSnapshot()
        {
            enqueueManualLyricsPersistence(snapshot, for: track, source: source)
        } else if project.baseLyrics.selectionReason == .manuallySelected {
            enqueueManualLyricsPersistence(project.baseLyrics, for: track, source: source)
        } else {
            enqueueManualLyricsPersistence(nil, for: track, source: source)
        }
    }

    private func replaceCurrentLyricsTimeline(
        with snapshot: LyricsSnapshot,
        for track: Track
    ) {
        let currentFingerprint = lyrics.timelineFingerprint(duration: track.duration)
        let replacementFingerprint = snapshot.timelineFingerprint(duration: track.duration)
        let preservesExistingTiming = currentFingerprint != nil
            && currentFingerprint == replacementFingerprint
        if !preservesExistingTiming {
            let offsetKey = TrackLyricOffsetStore.trackKey(for: track)
            stopOffsetCalibrationIfActive()
            calibrationRetryTask?.cancel()
            clearCalibrationCaptureContext()
            resetCalibrationEvidence()
            calibrationSucceededKeys.remove(offsetKey)
            trackOffsetStore.remove(forTrackKey: offsetKey)
            applyCurrentTrackOffset(nil)
            islandSyncState = .none
            offsetCalibrationStatusText = nil
        }
        lyrics = snapshot
        currentTranslation = nil
        lastTranslatedSource = nil
        pushOverlay()
        refreshTranslationIfNeeded()
    }

    // MARK: - Tap Sync

    func prepareTapSync() {
        guard nowPlaying.availability == .ready else {
            clearTapSyncSession(status: L10n.t("tap_sync.no_track"))
            return
        }

        let track = nowPlaying.track
        let source = nowPlaying.source
        let key = trackKey(nowPlaying)
        beginManualTimelineOperation()
        do {
            let project: TapSyncProject
            if let existing = tapSyncStore.project(
                for: track,
                source: source,
                matching: lyrics
            ) {
                project = existing
            } else if lyrics.availability == .plain, !lyrics.plainLines.isEmpty {
                project = try tapSyncStore.prepare(
                    for: track,
                    source: source,
                    lyrics: lyrics
                )
            } else {
                clearTapSyncSession(status: L10n.t("tap_sync.needs_plain_lyrics"))
                return
            }

            lyricsFetchTask?.cancel()
            lyricsFetchTask = nil
            isFetchingLyrics = false
            forcedCalibrationAfterLyricsFetchKey = nil
            tapSyncProject = project
            tapSyncTargetTrackKey = key
            tapSyncSelectedLineIndex = project.nextUnanchoredLineIndex()
                ?? project.nonEmptyLineIndices.first
            tapSyncStatusText = project.anchors.isEmpty
                ? L10n.t("tap_sync.ready")
                : L10n.t(
                    "tap_sync.progress",
                    project.anchors.count,
                    project.nonEmptyLineIndices.count
                )

            if !project.anchors.isEmpty, let resolved = try? project.syncedSnapshot() {
                replaceCurrentLyricsTimeline(with: resolved, for: track)
            }
            enqueueTapSyncPersistence(project, for: track, source: source)
        } catch {
            clearTapSyncSession(status: tapSyncMessage(for: error))
        }
    }

    func selectTapSyncLine(_ lineIndex: Int) {
        guard let project = tapSyncProject,
              project.nonEmptyLineIndices.contains(lineIndex)
        else { return }
        tapSyncSelectedLineIndex = lineIndex
    }

    func moveTapSyncSelection(by delta: Int) {
        guard let project = tapSyncProject, !project.nonEmptyLineIndices.isEmpty else { return }
        let indices = project.nonEmptyLineIndices
        let current = tapSyncSelectedLineIndex.flatMap { indices.firstIndex(of: $0) } ?? 0
        let next = min(indices.count - 1, max(0, current + delta))
        tapSyncSelectedLineIndex = indices[next]
    }

    func recordTapSyncAnchorNow() {
        guard validateTapSyncContext(),
              var project = tapSyncProject,
              let lineIndex = tapSyncSelectedLineIndex
        else { return }

        let rawPosition = playbackClock.position()
        let playbackTime = min(
            project.trackDuration ?? rawPosition,
            max(0, rawPosition)
        )
        do {
            beginManualTimelineOperation()
            try project.recordOrReplaceAnchor(
                lineIndex: lineIndex,
                playbackTime: playbackTime
            )
            tapSyncStore.set(project)
            tapSyncProject = project
            if let resolved = try? project.syncedSnapshot(), nowPlaying.availability == .ready {
                replaceCurrentLyricsTimeline(with: resolved, for: nowPlaying.track)
            }
            tapSyncSelectedLineIndex = project.nextUnanchoredLineIndex(after: lineIndex)
                ?? project.nextUnanchoredLineIndex()
            let progress = L10n.t(
                "tap_sync.progress",
                project.anchors.count,
                project.nonEmptyLineIndices.count
            )
            tapSyncStatusText = progress
            lyricsTimelineOperationStatusText = progress
            enqueueTapSyncPersistence(
                project,
                for: nowPlaying.track,
                source: nowPlaying.source
            )
        } catch {
            tapSyncStatusText = tapSyncMessage(for: error)
        }
    }

    func undoTapSyncAnchor() {
        guard validateTapSyncContext(), var project = tapSyncProject else { return }
        guard project.undoLastEdit() else { return }
        beginManualTimelineOperation()
        tapSyncStore.set(project)
        tapSyncProject = project
        if nowPlaying.availability == .ready {
            let snapshot = (try? project.syncedSnapshot()) ?? project.baseLyrics
            replaceCurrentLyricsTimeline(with: snapshot, for: nowPlaying.track)
        }
        tapSyncSelectedLineIndex = project.nextUnanchoredLineIndex()
            ?? project.nonEmptyLineIndices.first
        tapSyncStatusText = project.anchors.isEmpty
            ? L10n.t("tap_sync.ready")
            : L10n.t(
                "tap_sync.progress",
                project.anchors.count,
                project.nonEmptyLineIndices.count
            )
        lyricsTimelineOperationStatusText = tapSyncStatusText
        enqueueTapSyncPersistence(
            project,
            for: nowPlaying.track,
            source: nowPlaying.source
        )
    }

    func resetTapSyncProject() {
        guard validateTapSyncContext(), var project = tapSyncProject,
              nowPlaying.availability == .ready
        else { return }
        let track = nowPlaying.track
        let source = nowPlaying.source
        beginManualTimelineOperation()
        project.reset()
        tapSyncStore.set(project)
        tapSyncProject = project
        tapSyncSelectedLineIndex = project.nonEmptyLineIndices.first
        replaceCurrentLyricsTimeline(with: project.baseLyrics, for: track)
        tapSyncStatusText = L10n.t("tap_sync.reset_done")
        lyricsTimelineOperationStatusText = tapSyncStatusText
        enqueueTapSyncPersistence(project, for: track, source: source)
    }

    func finishTapSync() {
        guard validateTapSyncContext(), let project = tapSyncProject,
              !project.anchors.isEmpty, nowPlaying.availability == .ready
        else {
            tapSyncStatusText = L10n.t("tap_sync.no_anchors")
            return
        }
        let track = nowPlaying.track
        let source = nowPlaying.source
        beginManualTimelineOperation()
        do {
            let snapshot = try project.syncedSnapshot()
            tapSyncStore.set(project)
            replaceCurrentLyricsTimeline(with: snapshot, for: track)
            enqueueManualLyricsPersistence(snapshot, for: track, source: source)
            let complete = project.anchors.count == project.nonEmptyLineIndices.count
            let message = complete
                ? L10n.t("tap_sync.completed", project.anchors.count)
                : L10n.t(
                    "tap_sync.saved_partial",
                    project.anchors.count,
                    project.nonEmptyLineIndices.count
                )
            tapSyncStatusText = message
            lyricsTimelineOperationStatusText = message
        } catch {
            tapSyncStatusText = tapSyncMessage(for: error)
        }
    }

    func endTapSyncSession() {
        tapSyncProject = nil
        tapSyncSelectedLineIndex = nil
        tapSyncTargetTrackKey = nil
    }

    func tapSyncTogglePlayback() {
        guard validateTapSyncContext() else { return }
        let expectedKey = tapSyncTargetTrackKey
        Task { [weak self] in
            guard let self,
                  self.tapSyncTargetTrackKey == expectedKey,
                  self.validateTapSyncContext()
            else { return }
            await self.runPlayback(.playPause)
        }
    }

    func tapSyncSeekToStart() {
        guard validateTapSyncContext() else { return }
        let expectedKey = tapSyncTargetTrackKey
        Task { [weak self] in
            guard let self,
                  self.tapSyncTargetTrackKey == expectedKey,
                  self.validateTapSyncContext()
            else { return }
            await self.runSeek(to: 0)
        }
    }

    func tapSyncSeekBackward() {
        guard validateTapSyncContext() else { return }
        let expectedKey = tapSyncTargetTrackKey
        let target = max(0, playbackClock.position() - 5)
        Task { [weak self] in
            guard let self,
                  self.tapSyncTargetTrackKey == expectedKey,
                  self.validateTapSyncContext()
            else { return }
            await self.runSeek(to: target)
        }
    }

    private func validateTapSyncContext() -> Bool {
        guard nowPlaying.availability == .ready,
              let expected = tapSyncTargetTrackKey,
              trackKey(nowPlaying) == expected,
              let project = tapSyncProject,
              project.trackKey
                == TrackIdentity(track: nowPlaying.track, source: nowPlaying.source).storageKey
        else {
            clearTapSyncSession(status: L10n.t("tap_sync.track_changed"))
            return false
        }
        guard project.matches(
            lyrics: lyrics,
            duration: nowPlaying.track.duration
        ) else {
            clearTapSyncSession(status: L10n.t("tap_sync.lyrics_changed"))
            return false
        }
        return true
    }

    private func clearTapSyncSession(status: String? = nil) {
        tapSyncProject = nil
        tapSyncSelectedLineIndex = nil
        tapSyncTargetTrackKey = nil
        tapSyncStatusText = status
    }

    private func tapSyncMessage(for error: Error) -> String {
        guard let error = error as? TapSyncProjectError else {
            return L10n.t("tap_sync.invalid_project")
        }
        switch error {
        case .nonMonotonicAnchor:
            return L10n.t("tap_sync.non_monotonic")
        case .invalidPlaybackTime:
            return L10n.t("tap_sync.invalid_time")
        case .noAnchors:
            return L10n.t("tap_sync.no_anchors")
        case .lyricsFingerprintMismatch:
            return L10n.t("tap_sync.lyrics_changed")
        case .unsupportedLyrics, .noUsableLines, .missingLyricsFingerprint,
             .invalidLineIndex, .emptyLyricLine, .corruptProject:
            return L10n.t("tap_sync.invalid_project")
        }
    }

    // MARK: - Manual search

    func prepareLyricsSearch() {
        let ready = nowPlaying.availability == .ready
        lyricsSearch.prepare(
            for: ready ? nowPlaying.track : nil,
            trackKey: ready ? trackKey(nowPlaying) : nil
        )
    }

    func runLyricsSearch() {
        lyricsSearch.run(using: lyricsService)
    }

    func stopLyricsSearch() {
        lyricsSearch.stop()
    }

    /// Explicitly removes a manual pin. Ordinary refreshes intentionally keep
    /// the user's selected lyrics.
    func useAutomaticLyrics() {
        guard nowPlaying.availability == .ready else { return }
        let track = nowPlaying.track
        let source = nowPlaying.source
        let expectedTrackKey = trackKey(nowPlaying)
        let operationID = beginManualTimelineOperation()
        tapSyncStore.remove(for: track, source: nowPlaying.source)
        clearTapSyncSession()
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        isFetchingLyrics = false
        let lyricsService = self.lyricsService
        manualTimelineMutationQueue.enqueue { [weak self] in
            await lyricsService.removePinnedLyrics(for: track, source: source)
            guard let self else { return }
            guard self.nowPlaying.availability == .ready,
                  self.trackKey(self.nowPlaying) == expectedTrackKey,
                  self.manualTimelineRequestID == operationID
            else { return }
            await self.tick(forceLyrics: true)
        }
    }

    @discardableResult
    func applyLyricsSearchHit(_ hit: LyricsSearchHit) -> Bool {
        guard nowPlaying.availability == .ready else { return false }
        let currentTrackKey = trackKey(nowPlaying)
        guard lyricsSearch.canApply(to: currentTrackKey) else {
            lyricsSearch.trackDidChange(
                to: nowPlaying.track,
                trackKey: currentTrackKey
            )
            return false
        }
        // A same-track automatic fetch is validated only by track key. Cancel it
        // before pinning a manual result so it cannot arrive later and overwrite
        // the user's chosen timeline.
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        isFetchingLyrics = false
        pushOverlay()
        let track = nowPlaying.track
        let source = nowPlaying.source
        let expectedTrackKey = trackKey(nowPlaying)
        let operationID = beginManualTimelineOperation()
        tapSyncStore.remove(for: track, source: nowPlaying.source)
        clearTapSyncSession()
        let lyricsService = self.lyricsService
        manualTimelineMutationQueue.enqueue { [weak self] in
            let applied = await lyricsService.apply(
                hit: hit,
                to: track,
                source: source
            )
            guard let self,
                  self.trackKey(self.nowPlaying) == expectedTrackKey,
                  self.manualTimelineRequestID == operationID
            else { return }
            let offsetKey = TrackLyricOffsetStore.trackKey(for: track)
            self.stopOffsetCalibrationIfActive()
            self.calibrationRetryTask?.cancel()
            self.clearCalibrationCaptureContext()
            self.resetCalibrationEvidence()
            self.calibrationSucceededKeys.remove(offsetKey)
            self.lyrics = applied
            _ = self.reloadTrackAutoOffset(for: track)
            self.currentTranslation = nil
            self.lastTranslatedSource = nil
            self.pushOverlay()
            self.refreshTranslationIfNeeded()
            if applied.availability == .synced {
                let key = self.trackKey(self.nowPlaying)
                self.resetCalibrationEvidence(
                    for: offsetKey,
                    allowsRetryWhenDisabled: true
                )
                let result = self.maybeStartAutoCalibration(
                    for: track,
                    trackKey: key,
                    force: true
                )
                self.presentCalibrationStartResult(result, requestedByUser: true)
            }
        }
        return true
    }

    func setDisplayTraditionalChinese(_ value: Bool) {
        guard preferences.displayTraditionalChinese != value else { return }
        preferences.displayTraditionalChinese = value
        persist()
        pushOverlay()
    }

    func setLyricOffsetSeconds(_ value: Double) {
        let clamped = min(5, max(-5, value))
        guard abs(preferences.lyricOffsetSeconds - clamped) > 0.000_1 else { return }
        // A microphone pass is centered on the offset that was active when it
        // began. Do not persist a result across a user timeline change.
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence()
        preferences.lyricOffsetSeconds = clamped
        persist()
        pushOverlay()
    }

    /// Nudge lyric timeline by a fixed step (hotkey ⌘⇧] / ⌘⇧[).
    func nudgeLyricOffset(by seconds: Double) {
        setLyricOffsetSeconds(preferences.lyricOffsetSeconds + seconds)
    }

    func resetLyricOffset() {
        setLyricOffsetSeconds(0)
    }

    func setAutoCalibrateLyricOffset(_ value: Bool) {
        guard preferences.autoCalibrateLyricOffset != value else { return }
        preferences.autoCalibrateLyricOffset = value
        persist()
        if !value {
            stopOffsetCalibrationIfActive()
            calibrationRetryTask?.cancel()
            clearCalibrationCaptureContext()
            resetCalibrationEvidence()
            offsetCalibrationStatusText = nil
            islandSyncState = .none
            pushOverlay()
        } else if nowPlaying.availability == .ready {
            let result = maybeStartAutoCalibration(
                for: nowPlaying.track,
                trackKey: trackKey(nowPlaying),
                force: false
            )
            presentCalibrationStartResult(result, requestedByUser: false)
        }
    }

    /// Force a new mic alignment for the current track.
    func recalibrateCurrentTrackOffset() {
        guard nowPlaying.availability == .ready else {
            offsetCalibrationStatusText = L10n.t("offset_cal.need_playing")
            return
        }
        let track = nowPlaying.track
        let key = trackKey(nowPlaying)
        let offsetKey = TrackLyricOffsetStore.trackKey(for: track)
        _ = reloadTrackAutoOffset(for: track)
        // Keep the current working value until a new result is confirmed.
        stopOffsetCalibrationIfActive()
        calibrationSucceededKeys.remove(offsetKey)
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence(for: offsetKey, allowsRetryWhenDisabled: true)
        guard track.isPlaying || playbackClock.isPlaying else {
            presentCalibrationStartResult(.blocked(.paused), requestedByUser: true)
            pushOverlay()
            return
        }
        // Ensure we have synced lyrics first.
        if lyrics.availability != .synced {
            offsetCalibrationStatusText = L10n.t("offset_cal.waiting_lyrics")
            islandSyncState = .waiting
            forcedCalibrationAfterLyricsFetchKey = key
            startLyricsFetch(for: track, trackKey: key, alsoArtwork: false)
            pushOverlay()
            return
        }
        let result = maybeStartAutoCalibration(for: track, trackKey: key, force: true)
        presentCalibrationStartResult(result, requestedByUser: true)
        pushOverlay()
    }

    func clearCurrentTrackAutoOffset() {
        guard nowPlaying.availability == .ready else {
            offsetCalibrationStatusText = L10n.t("offset_cal.need_playing")
            return
        }
        let offsetKey = TrackLyricOffsetStore.trackKey(for: nowPlaying.track)
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence(for: offsetKey)
        trackOffsetStore.remove(forTrackKey: offsetKey)
        calibrationSucceededKeys.remove(offsetKey)
        applyCurrentTrackOffset(nil)
        offsetCalibrationStatusText = L10n.t("offset_cal.cleared")
        islandSyncState = .none
        pushOverlay()
    }

    /// Manual per-track nudge when auto mic align is wrong or unavailable (headphones).
    func nudgeTrackAutoOffset(by seconds: Double) {
        guard nowPlaying.availability == .ready else {
            offsetCalibrationStatusText = L10n.t("offset_cal.need_playing")
            return
        }
        let offsetKey = TrackLyricOffsetStore.trackKey(for: nowPlaying.track)
        guard let lyricsFingerprint = lyrics.timelineFingerprint(
            duration: nowPlaying.track.duration
        ) else {
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_few_lines")
            return
        }
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence(for: offsetKey)
        let current = currentTrackAutoOffsetSeconds ?? 0
        let next = min(6, max(-6, current + seconds))
        let entry = TrackLyricOffsetEntry(
            offsetSeconds: next,
            confidence: 1,
            source: "manual",
            lyricsFingerprint: lyricsFingerprint
        )
        applyCurrentTrackOffset(entry)
        calibrationSucceededKeys.insert(offsetKey)
        trackOffsetStore.set(entry, forTrackKey: offsetKey)
        offsetCalibrationStatusText = L10n.t(
            "offset_cal.track_offset",
            String(format: "%+.1f", next)
        )
        islandSyncState = .synced
        pushOverlay()
    }

    /// One-tap: treat the **next** non-empty lyric line as starting right now.
    /// Useful when auto mic align fails (headphones) — tap when the singer starts that phrase.
    func alignOffsetToNextLineNow() {
        guard nowPlaying.availability == .ready else {
            offsetCalibrationStatusText = L10n.t("offset_cal.need_playing")
            return
        }
        guard lyrics.availability == .synced || lyrics.availability == .plain else {
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_few_lines")
            return
        }
        let lines = lyrics.displayLines(duration: nowPlaying.track.duration)
        guard !lines.isEmpty else {
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_few_lines")
            return
        }
        let pos = playbackClock.position()
        let global = preferences.lyricOffsetSeconds
        let activePos = pos + global + (currentTrackAutoOffsetSeconds ?? 0)
        // Prefer the upcoming line; fall back to the active one.
        let target: LyricLine? =
            lines.first(where: {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.time > activePos + 0.05
            })
            ?? lines.last(where: {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.time <= activePos
            })
        guard let line = target else {
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_few_lines")
            return
        }
        // pos + global + trackOffset = line.time
        let trackOffset = min(6, max(-6, line.time - pos - global))
        let offsetKey = TrackLyricOffsetStore.trackKey(for: nowPlaying.track)
        guard let lyricsFingerprint = lyrics.timelineFingerprint(
            duration: nowPlaying.track.duration
        ) else {
            offsetCalibrationStatusText = L10n.t("offset_cal.skip_few_lines")
            return
        }
        stopOffsetCalibrationIfActive()
        calibrationRetryTask?.cancel()
        clearCalibrationCaptureContext()
        resetCalibrationEvidence(for: offsetKey)
        let entry = TrackLyricOffsetEntry(
            offsetSeconds: trackOffset,
            confidence: 1,
            source: "tap",
            lyricsFingerprint: lyricsFingerprint
        )
        applyCurrentTrackOffset(entry)
        calibrationSucceededKeys.insert(offsetKey)
        trackOffsetStore.set(entry, forTrackKey: offsetKey)
        offsetCalibrationStatusText = L10n.t(
            "offset_cal.success",
            String(format: "%+.1f", trackOffset),
            100
        )
        islandSyncState = .synced
        pushOverlay()
    }

    func setHideInFullscreen(_ value: Bool) {
        guard preferences.hideInFullscreen != value else { return }
        preferences.hideInFullscreen = value
        persist()
        pushOverlay()
    }

    func setLyricColorFromArtwork(_ value: Bool) {
        guard preferences.lyricColorFromArtwork != value else { return }
        preferences.lyricColorFromArtwork = value
        persist()
        pushOverlay()
    }

    func setIslandExtraWidth(_ value: Double) {
        let clamped = min(120, max(0, value))
        guard abs(preferences.islandExtraWidth - clamped) > 0.01 else { return }
        preferences.islandExtraWidth = clamped
        persist()
        applyOverlayPreferences()
        pushOverlay()
    }

    private func mutateAppearance(_ body: (inout OverlayAppearance) -> Void) {
        body(&preferences.appearance)
        preferences.appearance = OverlayAppearance(
            opacity: preferences.appearance.opacity,
            fontSize: preferences.appearance.fontSize,
            showTrackTitle: preferences.appearance.showTrackTitle,
            showAdjacentLines: preferences.appearance.showAdjacentLines,
            clickThrough: preferences.appearance.clickThrough,
            liquidGlassOnNotch: preferences.appearance.liquidGlassOnNotch,
            liquidGlassOnFloating: preferences.appearance.liquidGlassOnFloating,
            glassVariant: preferences.appearance.glassVariant
        )
        persist()
        applyOverlayPreferences()
        pushOverlay()
    }

    private func applyOverlayPreferences() {
        overlay.apply(
            appearance: preferences.appearance,
            screenPlacement: preferences.screenPlacement,
            verticalOffset: preferences.verticalOffset,
            islandExtraWidth: preferences.islandExtraWidth
        )
        overlay.setVisible(shouldPresentOverlay)
    }

    private func persist() {
        store.save(preferences)
    }

    private func configureHotKey() {
        let monitor = GlobalHotKeyMonitor.shared
        monitor.stop()
        if preferences.hotKeyEnabled {
            monitor.onToggleVisibility = { [weak self] in
                Task { @MainActor [weak self] in self?.toggleOverlay() }
            }
            monitor.onToggleExpand = { [weak self] in
                Task { @MainActor [weak self] in self?.toggleExpand() }
            }
            monitor.onLyricDelayPlus = { [weak self] in
                Task { @MainActor [weak self] in self?.nudgeLyricOffset(by: 0.5) }
            }
            monitor.onLyricDelayMinus = { [weak self] in
                Task { @MainActor [weak self] in self?.nudgeLyricOffset(by: -0.5) }
            }
            monitor.start()
            hotKeyStatusText = monitor.isRegistered
                ? L10n.t("hotkey.on")
                : L10n.t("hotkey.fail")
        } else {
            monitor.onToggleVisibility = nil
            monitor.onToggleExpand = nil
            monitor.onLyricDelayPlus = nil
            monitor.onLyricDelayMinus = nil
            hotKeyStatusText = L10n.t("hotkey.off")
        }
    }

    private func refreshLaunchAtLoginStatus() {
        switch LaunchAtLogin.status {
        case .enabled:
            launchAtLoginStatusText = L10n.t("login.on")
        case .disabled:
            launchAtLoginStatusText = L10n.t("login.off")
        case .requiresApproval:
            launchAtLoginStatusText = L10n.t("login.approval")
        case .notAvailable(let message):
            // Prefer localized “need packaged app” when message matches the known case.
            if message.contains("swift run") || message.contains("Lyrinotch.app") {
                launchAtLoginStatusText = L10n.t("login.need_app")
            } else {
                launchAtLoginStatusText = message
            }
        }
    }

    private func trackKey(_ snap: NowPlayingSnapshot) -> String {
        switch snap.availability {
        case .ready:
            return "ready|\(TrackIdentity(track: snap.track, source: snap.source).storageKey)"
        case .playerNotRunning, .noTrack, .error:
            return snap.availability.rawValue
        }
    }

    private func statusMessage(for snap: NowPlayingSnapshot, lyrics: LyricsSnapshot) -> String? {
        guard snap.availability == .ready else { return nil }

        switch lyrics.availability {
        case .synced:
            return nil
        case .plain:
            // Plain lines are estimated onto a timeline and shown as normal lyrics.
            return nil
        case .instrumental:
            return L10n.t("status.instrumental")
        case .notFound:
            return L10n.t("status.not_found")
        case .error:
            return L10n.t("status.fetch_failed")
        case .skipped:
            return nil
        }
    }

}
