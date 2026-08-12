import Foundation

/// One microphone-derived estimate of the total timeline offset needed for a track.
public struct LyricCalibrationSample: Equatable, Sendable {
    public var totalOffset: Double
    public var confidence: Double

    public init(totalOffset: Double, confidence: Double) {
        self.totalOffset = totalOffset
        self.confidence = min(1, max(0, confidence))
    }
}

/// Decides when a noisy microphone estimate is safe enough to affect the playhead.
public enum LyricCalibrationDecision: Equatable, Sendable {
    /// A very strong result, or two independent results that agree.
    case apply(LyricCalibrationSample)
    /// Keep the current offset unchanged and collect one more window.
    case waitForConfirmation(LyricCalibrationSample)
    /// Evidence is too weak to use.
    case reject
}

public enum LyricCalibrationPolicy {
    /// A single result at this confidence can be applied immediately.
    public static let immediateConfidence = 0.80
    /// Results below the trusted persistence gate must never move the playhead,
    /// even when the same song structure makes them repeat in another window.
    public static let confirmationConfidence = LyricOffsetAligner.micPersistMinConfidence
    /// Two estimates are considered the same correction within this tolerance.
    public static let agreementTolerance: TimeInterval = 0.20
    /// Prevent continuous microphone capture on tracks that cannot be aligned reliably.
    public static let maxAutomaticAttempts = 3
    /// Legacy automatic values below this confidence must not move the timeline.
    public static let minimumStoredAutomaticConfidence =
        LyricOffsetAligner.micPersistMinConfidence
    /// Speaker/microphone latency can change after system or routing changes.
    /// Re-measure old automatic values instead of treating them as permanent truth.
    public static let maximumStoredAutomaticAge: TimeInterval = 30 * 24 * 60 * 60

    public static func allowsAnotherAttempt(afterStartedAttempts count: Int) -> Bool {
        max(0, count) < maxAutomaticAttempts
    }

    /// Manual values reflect an explicit user action. Automatic values from older
    /// app versions are only safe to reuse if they passed the persistence gate.
    public static func acceptsStoredOffset(source: String, confidence: Double) -> Bool {
        switch source {
        case "manual", "tap":
            return true
        case "auto":
            return confidence >= minimumStoredAutomaticConfidence
        default:
            return false
        }
    }

    /// Validates a persisted correction against the exact timeline and playback
    /// environment it was measured with. Legacy entries have no fingerprint or
    /// route and are deliberately retired on their next load.
    public static func acceptsStoredOffset(
        _ entry: TrackLyricOffsetEntry,
        lyricsFingerprint: String,
        audioRoute: String,
        now: Date = Date()
    ) -> Bool {
        guard !lyricsFingerprint.isEmpty,
              entry.offsetSeconds.isFinite,
              entry.confidence.isFinite,
              entry.lyricsFingerprint == lyricsFingerprint,
              acceptsStoredOffset(source: entry.source, confidence: entry.confidence)
        else { return false }

        switch entry.source {
        case "manual", "tap":
            // Explicit user corrections are tied to the lyrics, but not to the
            // speaker route because they do not measure acoustic latency.
            return true
        case "auto":
            let age = now.timeIntervalSince(entry.updatedAt)
            return age >= -300
                && age <= maximumStoredAutomaticAge
                && entry.audioRoute == audioRoute
        default:
            return false
        }
    }

    public static func evaluate(
        previous: LyricCalibrationSample?,
        new sample: LyricCalibrationSample
    ) -> LyricCalibrationDecision {
        if sample.confidence >= immediateConfidence {
            return .apply(sample)
        }
        guard sample.confidence >= confirmationConfidence else {
            return .reject
        }
        guard let previous else {
            return .waitForConfirmation(sample)
        }
        guard abs(previous.totalOffset - sample.totalOffset) <= agreementTolerance else {
            // Retain the stronger candidate so a third bounded attempt can confirm it.
            return .waitForConfirmation(
                previous.confidence >= sample.confidence ? previous : sample
            )
        }

        let weight = max(0.000_1, previous.confidence + sample.confidence)
        let offset = (
            previous.totalOffset * previous.confidence
                + sample.totalOffset * sample.confidence
        ) / weight
        // Two windows from the same mix are correlated (the same beat can win in
        // both), so agreement confirms the offset but must not inflate its quality.
        let confidence = max(previous.confidence, sample.confidence)
        return .apply(LyricCalibrationSample(totalOffset: offset, confidence: confidence))
    }

    /// Mic matching measures the total `playback + offset` correction. The stored
    /// per-track value must therefore exclude the already-applied global preference.
    public static func trackResidual(
        measuredTotalOffset: TimeInterval,
        globalOffset: TimeInterval,
        maximumMagnitude: TimeInterval = 6
    ) -> TimeInterval {
        let limit = max(0, maximumMagnitude)
        return min(limit, max(-limit, measuredTotalOffset - globalOffset))
    }
}
