import Foundation

public enum LyricsAvailability: String, Codable, Sendable, Equatable {
    /// Timed LRC lines available.
    case synced
    /// Only plain (untimed) lyrics available.
    case plain
    /// Track is instrumental / no vocal lyrics.
    case instrumental
    /// Provider has no match.
    case notFound
    /// Network / parse / unexpected failure.
    case error
    /// Track metadata insufficient to query.
    case skipped
}

/// Why the multi-source selector chose the displayed lyrics.
public enum LyricsSelectionReason: String, Codable, Sendable, Equatable {
    case playerEmbedded
    case strongSyncedMatch
    case languageMatch
    case fallbackSource
    case plainTextFallback
    case manuallySelected

    public var displayNameKey: String {
        switch self {
        case .playerEmbedded: return "lyrics_reason.player_embedded"
        case .strongSyncedMatch: return "lyrics_reason.strong_synced"
        case .languageMatch: return "lyrics_reason.language_match"
        case .fallbackSource: return "lyrics_reason.fallback_source"
        case .plainTextFallback: return "lyrics_reason.plain_fallback"
        case .manuallySelected: return "lyrics_reason.manual"
        }
    }
}

/// Provider-reported identity for the record that supplied a lyrics snapshot.
/// Keeping this structured avoids treating diagnostic text as matching data.
public struct LyricsMatchMetadata: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String
    public var duration: TimeInterval?
    public var providerID: String?

    public init(
        title: String,
        artist: String,
        duration: TimeInterval? = nil,
        providerID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.providerID = providerID
    }
}

public struct LyricsSnapshot: Codable, Sendable, Equatable {
    public var availability: LyricsAvailability
    /// Timed lines when `availability == .synced`.
    public var lines: [LyricLine]
    /// Untimed fallback lines when only plain lyrics exist.
    public var plainLines: [String]
    public var source: String?
    public var detail: String?
    public var matchedTrack: LyricsMatchMetadata?
    public var selectionReason: LyricsSelectionReason?
    /// Fingerprint of the provider/plain timeline that a manually timed snapshot
    /// was derived from. This remains separate from `timelineFingerprint`: the
    /// latter must still change whenever an edited timestamp changes.
    ///
    /// Tap-sync uses this value to reopen a persisted editing project when the
    /// currently pinned lyrics are the generated `manual-tap` snapshot rather
    /// than the original untimed lyrics.
    public var timingBaseFingerprint: String?

    public init(
        availability: LyricsAvailability,
        lines: [LyricLine] = [],
        plainLines: [String] = [],
        source: String? = nil,
        detail: String? = nil,
        matchedTrack: LyricsMatchMetadata? = nil,
        selectionReason: LyricsSelectionReason? = nil,
        timingBaseFingerprint: String? = nil
    ) {
        self.availability = availability
        self.lines = lines
        self.plainLines = plainLines
        self.source = source
        self.detail = detail
        self.matchedTrack = matchedTrack
        self.selectionReason = selectionReason
        self.timingBaseFingerprint = timingBaseFingerprint
    }

    public static let skipped = LyricsSnapshot(
        availability: .skipped,
        detail: "Track metadata incomplete"
    )

    /// Stable identity for the timing data actually shown to the user.
    ///
    /// Per-track offsets must be tied to this value, not only to the player track ID:
    /// two providers (or two edits of one provider record) can return different LRC
    /// timestamps for the same recording. FNV-1a is intentionally used instead of
    /// Swift's randomized `Hasher` so the value remains stable across app launches.
    public func timelineFingerprint(duration: TimeInterval?) -> String? {
        func milliseconds(_ value: TimeInterval) -> Int64? {
            let scaled = value * 1_000
            guard scaled.isFinite,
                  scaled >= Double(Int64.min),
                  scaled < Double(Int64.max)
            else { return nil }
            return Int64(scaled.rounded())
        }

        var components = [
            "timeline-v1",
            availability.rawValue,
            source?.lowercased() ?? "-",
            matchedTrack?.providerID ?? "-"
        ]

        switch availability {
        case .synced where !lines.isEmpty:
            var encodedLines: [String] = []
            encodedLines.reserveCapacity(lines.count)
            for line in lines {
                guard let lineMilliseconds = milliseconds(line.time) else { return nil }
                encodedLines.append(
                    "\(lineMilliseconds)|\(line.text.trimmingCharacters(in: .whitespacesAndNewlines))"
                )
            }
            components.append(contentsOf: encodedLines)
        case .plain where !plainLines.isEmpty:
            let durationMilliseconds: Int64
            if let duration {
                guard let encodedDuration = milliseconds(duration) else { return nil }
                durationMilliseconds = encodedDuration
            } else {
                durationMilliseconds = -1
            }
            components.append("duration|\(durationMilliseconds)")
            components.append(contentsOf: plainLines.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })
        default:
            return nil
        }

        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in components.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "v1:%016llx", hash)
    }

    /// Active lyric text for a playback position.
    /// - Synced: LRC timeline.
    /// - Plain: estimate line index from position/duration so the HUD still shows words.
    public func activeText(at position: TimeInterval?, duration: TimeInterval? = nil) -> String? {
        let display = displayLines(duration: duration)
        guard !display.isEmpty else { return nil }
        let pos = position ?? 0
        guard let index = LyricLine.activeIndex(in: display, at: pos) else {
            // Before first timed line — show first non-empty line for plain estimates.
            if availability == .plain {
                return display.first?.text
            }
            return nil
        }
        let text = display[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Lines used for HUD display (real LRC or duration-estimated plain lines).
    public func displayLines(duration: TimeInterval?) -> [LyricLine] {
        if availability == .synced, !lines.isEmpty {
            return lines
        }
        if availability == .plain, !plainLines.isEmpty {
            return Self.estimateTimedLines(from: plainLines, duration: duration)
        }
        return lines
    }

    /// Spread plain lyric lines evenly across the track duration.
    public static func estimateTimedLines(from plain: [String], duration: TimeInterval?) -> [LyricLine] {
        guard !plain.isEmpty else { return [] }
        let fallback = Double(plain.count) * 4.0
        let dur = max(LyricsInputLimits.validDuration(duration) ?? fallback, 1.0)
        let step = dur / Double(plain.count)
        return plain.enumerated().map { index, text in
            LyricLine(time: Double(index) * step, text: text)
        }
    }
}
