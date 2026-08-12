import Foundation

/// Interpolates playback position between sparse player polls (AppleScript).
///
/// Spotify/Music position is only sampled ~every 0.5–1s, and lyrics fetches can
/// stall that loop for several seconds. While playing, we advance a local clock
/// so lyrics stay aligned with the audio instead of freezing at the last sample.
public struct PlaybackClock: Sendable, Equatable {
    public var sampledPosition: TimeInterval
    public var sampledAt: Date
    public var isPlaying: Bool
    public var duration: TimeInterval?
    private var sampledTrackIdentity: TrackIdentity?

    public init(
        sampledPosition: TimeInterval = 0,
        sampledAt: Date = .distantPast,
        isPlaying: Bool = false,
        duration: TimeInterval? = nil
    ) {
        self.sampledPosition = max(0, sampledPosition)
        self.sampledAt = sampledAt
        self.isPlaying = isPlaying
        self.duration = duration
        self.sampledTrackIdentity = nil
    }

    public mutating func sample(
        position: TimeInterval?,
        isPlaying: Bool,
        duration: TimeInterval?,
        at date: Date = Date()
    ) {
        // A position-only sample cannot prove it belongs to the previously
        // identified track. Keep this API for callers without track metadata,
        // but disable cross-call stale-sample assumptions for it.
        sampledTrackIdentity = nil
        let reported = max(0, position ?? 0)
        // Reconcile ordinary AppleScript jitter gradually. Ignoring every small
        // backward delta leaves the clock permanently ahead after an external
        // short seek; snapping every sample makes lyric lines flicker.
        if self.isPlaying, isPlaying, sampledAt != .distantPast {
            let estimated = self.position(at: date)
            let delta = reported - estimated
            if abs(delta) < 1.5 {
                let deadband = 0.08
                let correction = abs(delta) <= deadband ? 0 : delta * 0.35
                sampledPosition = max(0, estimated + correction)
                sampledAt = date
                self.isPlaying = isPlaying
                self.duration = duration
                return
            }
        }
        sampledPosition = reported
        sampledAt = date
        self.isPlaying = isPlaying
        self.duration = duration
    }

    /// Applies a player sample, rejecting samples older than the current sample
    /// when both belong to the same track.
    ///
    /// - Returns: `true` when the sample was applied, or `false` when it was stale.
    @discardableResult
    public mutating func sample(
        from track: Track,
        source: MusicPlayerSource? = nil,
        at date: Date = Date()
    ) -> Bool {
        let identity = TrackIdentity(track: track, source: source)
        let sampleDate = track.positionSampledAt ?? date

        if sampledTrackIdentity == identity {
            guard sampleDate >= sampledAt else { return false }
            sample(
                position: track.position,
                isPlaying: track.isPlaying,
                duration: track.duration,
                at: sampleDate
            )
        } else {
            // A different track must not be reconciled against the previous
            // song's playhead, even if its sample was captured slightly earlier.
            sampledPosition = max(0, track.position ?? 0)
            sampledAt = sampleDate
            isPlaying = track.isPlaying
            duration = track.duration
        }
        sampledTrackIdentity = identity
        return true
    }

    /// Seek / optimistic update without waiting for the next player poll.
    public mutating func seek(to position: TimeInterval, at date: Date = Date()) {
        sampledPosition = max(0, position)
        sampledAt = date
    }

    public mutating func setPlaying(_ playing: Bool, at date: Date = Date()) {
        // Fold elapsed time into the sample before flipping pause/play.
        sampledPosition = position(at: date)
        sampledAt = date
        isPlaying = playing
    }

    /// Estimated playhead at `date` (defaults to now).
    public func position(at date: Date = Date()) -> TimeInterval {
        var pos = sampledPosition
        if isPlaying, sampledAt != .distantPast {
            pos += date.timeIntervalSince(sampledAt)
        }
        if let duration, duration > 0 {
            pos = min(pos, duration)
        }
        return max(0, pos)
    }
}
