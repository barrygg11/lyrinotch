import Foundation

/// Reads the currently playing track from **Spotify** and/or **Apple Music** via AppleScript.
///
/// Requires macOS Automation permission for the terminal / app to control each player
/// (System Settings → Privacy & Security → Automation).
public actor NowPlayingService {
    private enum TaggedFetch: Sendable {
        case primary(NowPlayingSnapshot)
        case secondary(NowPlayingSnapshot)
        case fallbackDeadline
    }

    private let executor: any AppleScriptExecuting
    private let fallbackHedgeDelayNanoseconds: UInt64
    private let fallbackPrimaryGraceNanoseconds: UInt64
    /// Sticky source avoids spawning and waiting for both player scripts on every
    /// poll once one player is confirmed to be actively playing.
    private var activeSource: MusicPlayerSource?

    public init(
        executor: any AppleScriptExecuting = ProcessAppleScriptExecutor(),
        fallbackHedgeDelayMilliseconds: Int = 200,
        fallbackPrimaryGraceMilliseconds: Int = 300
    ) {
        self.executor = executor
        self.fallbackHedgeDelayNanoseconds = UInt64(
            min(4_000, max(0, fallbackHedgeDelayMilliseconds))
        ) * 1_000_000
        self.fallbackPrimaryGraceNanoseconds = UInt64(
            min(4_000, max(0, fallbackPrimaryGraceMilliseconds))
        ) * 1_000_000
    }

    /// Full snapshot: prefers a playing track from either player.
    public func snapshot(
        preferredSource: MusicPlayerSource? = nil
    ) async -> NowPlayingSnapshot {
        if let primarySource = preferredSource ?? activeSource {
            let combined = await fetchStickyPair(
                primarySource: primarySource,
                preferredSource: preferredSource ?? activeSource
            )
            remember(combined)
            return combined
        }

        let combined = await fetchInitialPair()
        remember(combined)
        return combined
    }

    /// Convenience: track when ready, otherwise `Track.empty`.
    public func currentTrack() async -> Track {
        let snap = await snapshot()
        return snap.availability == .ready ? snap.track : .empty
    }

    // MARK: - Per-player

    private func fetch(_ source: MusicPlayerSource) async -> NowPlayingSnapshot {
        switch source {
        case .spotify: return await fetchSpotify()
        case .appleMusic: return await fetchMusic()
        }
    }

    /// On the first poll there is no sticky player yet. Return as soon as either
    /// player confirms active playback instead of waiting for an unrelated hung
    /// AppleScript. Idle/error results still wait for the other side so a loaded
    /// or playing track is not hidden.
    private func fetchInitialPair() async -> NowPlayingSnapshot {
        await withTaskGroup(
            of: TaggedFetch.self,
            returning: NowPlayingSnapshot.self
        ) { group in
            group.addTask { [self] in .primary(await fetchSpotify()) }
            group.addTask { [self] in .secondary(await fetchMusic()) }

            var spotify: NowPlayingSnapshot?
            var music: NowPlayingSnapshot?
            for await tagged in group {
                let snapshot: NowPlayingSnapshot
                switch tagged {
                case .primary(let result):
                    spotify = result
                    snapshot = result
                case .secondary(let result):
                    music = result
                    snapshot = result
                case .fallbackDeadline:
                    continue
                }
                if snapshot.availability == .ready, snapshot.track.isPlaying {
                    group.cancelAll()
                    return snapshot
                }
                if let spotify, let music {
                    group.cancelAll()
                    return NowPlayingSelector.pick(spotify: spotify, music: music)
                }
            }
            return spotify ?? music ?? .playerNotRunning
        }
    }

    /// Query the sticky player first, but hedge with the other player when that
    /// AppleScript is slow. A healthy primary normally finishes before the hedge
    /// starts, preserving the one-process fast path; a hung primary no longer
    /// delays the real playing source by two serial four-second timeouts.
    private func fetchStickyPair(
        primarySource: MusicPlayerSource,
        preferredSource: MusicPlayerSource?
    ) async -> NowPlayingSnapshot {
        let secondarySource = primarySource.other
        let hedgeDelay = fallbackHedgeDelayNanoseconds
        let primaryGrace = fallbackPrimaryGraceNanoseconds

        return await withTaskGroup(
            of: TaggedFetch?.self,
            returning: NowPlayingSnapshot.self
        ) { group in
            group.addTask { [self] in
                .primary(await fetch(primarySource))
            }
            group.addTask { [self] in
                if hedgeDelay > 0 {
                    try? await Task.sleep(nanoseconds: hedgeDelay)
                    guard !Task.isCancelled else { return nil }
                }
                return .secondary(await fetch(secondarySource))
            }
            group.addTask {
                let deadline = hedgeDelay + primaryGrace
                if deadline > 0 {
                    try? await Task.sleep(nanoseconds: deadline)
                    guard !Task.isCancelled else { return nil }
                }
                return .fallbackDeadline
            }

            var primary: NowPlayingSnapshot?
            var secondary: NowPlayingSnapshot?
            var fallbackDeadlinePassed = false
            for await next in group {
                guard let tagged = next else { continue }
                switch tagged {
                case .primary(let result):
                    primary = result
                    if result.availability == .ready, result.track.isPlaying {
                        group.cancelAll()
                        return result
                    }
                    if let secondary,
                       secondary.availability == .ready,
                       secondary.track.isPlaying
                    {
                        group.cancelAll()
                        return secondary
                    }
                case .secondary(let result):
                    secondary = result
                    // A fast secondary must not steal selection from a preferred
                    // or sticky primary whose playing response is only slightly
                    // slower. Once the primary is known not to be playing, the
                    // active secondary can win immediately.
                    if primary != nil,
                       result.availability == .ready,
                       result.track.isPlaying
                    {
                        group.cancelAll()
                        return result
                    }
                    if primary == nil,
                       fallbackDeadlinePassed,
                       result.availability == .ready,
                       result.track.isPlaying
                    {
                        group.cancelAll()
                        return result
                    }
                case .fallbackDeadline:
                    fallbackDeadlinePassed = true
                    if primary == nil,
                       let secondary,
                       secondary.availability == .ready,
                       secondary.track.isPlaying
                    {
                        group.cancelAll()
                        return secondary
                    }
                }
                if let primary, let secondary {
                    group.cancelAll()
                    return select(
                        primary: primary,
                        secondary: secondary,
                        primarySource: primarySource,
                        preferredSource: preferredSource
                    )
                }
            }

            // Both tasks normally produce a result. Keep a defensive fallback
            // for cancellation during teardown.
            return primary ?? secondary ?? .playerNotRunning
        }
    }

    private func select(
        primary: NowPlayingSnapshot,
        secondary: NowPlayingSnapshot,
        primarySource: MusicPlayerSource,
        preferredSource: MusicPlayerSource?
    ) -> NowPlayingSnapshot {
        switch primarySource {
        case .spotify:
            return NowPlayingSelector.pick(
                spotify: primary,
                music: secondary,
                preferredSource: preferredSource
            )
        case .appleMusic:
            return NowPlayingSelector.pick(
                spotify: secondary,
                music: primary,
                preferredSource: preferredSource
            )
        }
    }

    private func remember(_ snapshot: NowPlayingSnapshot) {
        if snapshot.availability == .ready {
            activeSource = snapshot.source
        } else if snapshot.availability == .playerNotRunning {
            activeSource = nil
        }
    }

    private func fetchSpotify() async -> NowPlayingSnapshot {
        do {
            let raw = try await executor.run(script: SpotifyAppleScript.nowPlayingScript)
            return SpotifyNowPlayingParser.parse(raw)
        } catch {
            return NowPlayingSnapshot(
                availability: .error,
                detail: error.localizedDescription,
                source: .spotify
            )
        }
    }

    private func fetchMusic() async -> NowPlayingSnapshot {
        do {
            let raw = try await executor.run(script: MusicAppleScript.nowPlayingScript)
            return MusicNowPlayingParser.parse(raw)
        } catch {
            return NowPlayingSnapshot(
                availability: .error,
                detail: error.localizedDescription,
                source: .appleMusic
            )
        }
    }
}
