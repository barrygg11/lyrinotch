import Foundation

/// A user-recorded start time for one lyric line.
public struct TapSyncAnchor: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { lineIndex }
    public var lineIndex: Int
    public var playbackTime: TimeInterval

    public init(lineIndex: Int, playbackTime: TimeInterval) {
        self.lineIndex = lineIndex
        self.playbackTime = playbackTime
    }
}

/// Recoverable validation failures for the tap-sync editing workflow.
public enum TapSyncProjectError: Error, Equatable, Sendable {
    case unsupportedLyrics
    case noUsableLines
    case missingLyricsFingerprint
    case invalidLineIndex
    case emptyLyricLine
    case invalidPlaybackTime
    case nonMonotonicAnchor
    case noAnchors
    case lyricsFingerprintMismatch
    case corruptProject
}

/// Persistable editing state for assigning real playback times to lyric lines.
///
/// `trackKey` prevents state crossing player/catalog boundaries, while
/// `baseLyricsFingerprint` prevents anchors from being applied to another
/// provider result (or a changed edit of the same result).
public struct TapSyncProject: Codable, Equatable, Sendable {
    public static let outputSource = "manual-tap"
    public static let currentSchemaVersion = 1

    public private(set) var trackKey: String
    public private(set) var baseLyricsFingerprint: String
    public private(set) var baseLyrics: LyricsSnapshot
    public private(set) var trackDuration: TimeInterval?
    public private(set) var anchors: [TapSyncAnchor]
    public private(set) var updatedAt: Date

    private var undoStack: [Edit]

    private struct Edit: Codable, Equatable, Sendable {
        var lineIndex: Int
        var previousAnchor: TapSyncAnchor?
    }

    /// Starts a fresh project from the exact lyrics currently shown for a track.
    /// Generated `manual-tap` output should be resumed from `TapSyncProjectStore`
    /// instead, because its original provider snapshot lives in that project.
    public init(
        track: Track,
        source: MusicPlayerSource? = nil,
        lyrics: LyricsSnapshot,
        updatedAt: Date = Date()
    ) throws {
        guard lyrics.source != Self.outputSource,
              lyrics.timingBaseFingerprint == nil
        else { throw TapSyncProjectError.unsupportedLyrics }

        let duration = Self.normalizedDuration(track.duration)
        guard let texts = Self.supportedLines(in: lyrics) else {
            throw TapSyncProjectError.unsupportedLyrics
        }
        guard texts.contains(where: Self.isNonEmpty) else {
            throw TapSyncProjectError.noUsableLines
        }
        guard let fingerprint = lyrics.timelineFingerprint(duration: duration) else {
            throw TapSyncProjectError.missingLyricsFingerprint
        }

        trackKey = TrackIdentity(track: track, source: source).storageKey
        baseLyricsFingerprint = fingerprint
        baseLyrics = lyrics
        trackDuration = duration
        anchors = []
        self.updatedAt = updatedAt
        undoStack = []
    }

    /// Text rows in the stable order used by anchor line indices.
    public var lineTexts: [String] {
        Self.supportedLines(in: baseLyrics) ?? []
    }

    public var nonEmptyLineIndices: [Int] {
        lineTexts.indices.filter { Self.isNonEmpty(lineTexts[$0]) }
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    /// Returns the first usable, unanchored row after `lineIndex`.
    public func nextUnanchoredLineIndex(after lineIndex: Int = -1) -> Int? {
        let anchored = Set(anchors.map(\.lineIndex))
        return nonEmptyLineIndices.first { $0 > lineIndex && !anchored.contains($0) }
    }

    /// Records a new anchor or replaces the existing anchor at the same row.
    /// `playbackTime` is the player's raw song position; callers must not add
    /// global/per-track lyric offsets. Neighboring anchors must remain strictly
    /// increasing in playback time.
    @discardableResult
    public mutating func recordOrReplaceAnchor(
        lineIndex: Int,
        playbackTime: TimeInterval,
        updatedAt: Date = Date()
    ) throws -> TapSyncAnchor {
        let texts = lineTexts
        guard texts.indices.contains(lineIndex) else {
            throw TapSyncProjectError.invalidLineIndex
        }
        guard Self.isNonEmpty(texts[lineIndex]) else {
            throw TapSyncProjectError.emptyLyricLine
        }
        guard playbackTime.isFinite, playbackTime >= 0,
              trackDuration.map({ playbackTime <= $0 }) ?? true
        else { throw TapSyncProjectError.invalidPlaybackTime }

        let previous = anchors.last { $0.lineIndex < lineIndex }
        let next = anchors.first { $0.lineIndex > lineIndex }
        guard previous.map({ $0.playbackTime < playbackTime }) ?? true,
              next.map({ playbackTime < $0.playbackTime }) ?? true
        else { throw TapSyncProjectError.nonMonotonicAnchor }

        let newAnchor = TapSyncAnchor(lineIndex: lineIndex, playbackTime: playbackTime)
        let oldAnchor = anchors.first { $0.lineIndex == lineIndex }
        if oldAnchor == newAnchor { return newAnchor }

        undoStack.append(Edit(lineIndex: lineIndex, previousAnchor: oldAnchor))
        if undoStack.count > 2_000 {
            undoStack.removeFirst(undoStack.count - 2_000)
        }
        anchors.removeAll { $0.lineIndex == lineIndex }
        anchors.append(newAnchor)
        anchors.sort { $0.lineIndex < $1.lineIndex }
        self.updatedAt = updatedAt
        return newAnchor
    }

    /// Reverts the most recent add/replace operation, including after restart.
    @discardableResult
    public mutating func undoLastEdit(updatedAt: Date = Date()) -> Bool {
        guard let edit = undoStack.popLast() else { return false }
        anchors.removeAll { $0.lineIndex == edit.lineIndex }
        if let previous = edit.previousAnchor {
            anchors.append(previous)
            anchors.sort { $0.lineIndex < $1.lineIndex }
        }
        self.updatedAt = updatedAt
        return true
    }

    /// Discards all recorded timing while retaining the original lyrics.
    public mutating func reset(updatedAt: Date = Date()) {
        anchors.removeAll(keepingCapacity: true)
        undoStack.removeAll(keepingCapacity: true)
        self.updatedAt = updatedAt
    }

    /// True for either the original provider snapshot or a generated snapshot
    /// derived from the same base lyrics. A pinned output may contain an older
    /// project revision when the user closes mid-edit; the persisted project is
    /// authoritative in that case, so base fingerprint + ordered text identity
    /// intentionally wins over comparing the stale generated timestamps.
    public func matches(lyrics: LyricsSnapshot, duration _: TimeInterval?) -> Bool {
        if lyrics.timingBaseFingerprint == baseLyricsFingerprint,
           lyrics.source == Self.outputSource,
           lyrics.lines.map(\.text) == lineTexts
        {
            return true
        }
        // Plain lyric fingerprints include duration. Player samples can drift by
        // milliseconds or temporarily omit duration, so compare against the
        // duration captured with the project rather than the latest poll.
        return lyrics.timelineFingerprint(duration: trackDuration)
            == baseLyricsFingerprint
    }

    /// Piecewise-interpolated line timeline. Recorded anchors remain exact.
    public func resolvedLines() throws -> [LyricLine] {
        try TapSyncTimelineResolver.resolve(project: self)
    }

    /// A regular synced snapshot suitable for display or pinning.
    public func syncedSnapshot() throws -> LyricsSnapshot {
        let lines = try resolvedLines()
        return LyricsSnapshot(
            availability: .synced,
            lines: lines,
            source: Self.outputSource,
            detail: "tap-sync:\(anchors.count)/\(nonEmptyLineIndices.count)",
            matchedTrack: baseLyrics.matchedTrack,
            selectionReason: .manuallySelected,
            timingBaseFingerprint: baseLyricsFingerprint
        )
    }

    // MARK: - Persistence validation

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case trackKey
        case baseLyricsFingerprint
        case baseLyrics
        case trackDuration
        case anchors
        case updatedAt
        case undoStack
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version == Self.currentSchemaVersion else {
            throw TapSyncProjectError.corruptProject
        }

        let decodedTrackKey = try values.decode(String.self, forKey: .trackKey)
        let decodedFingerprint = try values.decode(String.self, forKey: .baseLyricsFingerprint)
        let decodedLyrics = try values.decode(LyricsSnapshot.self, forKey: .baseLyrics)
        let decodedDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .trackDuration)
        let decodedAnchors = try values.decode([TapSyncAnchor].self, forKey: .anchors)
        let decodedUpdatedAt = try values.decode(Date.self, forKey: .updatedAt)
        let decodedUndo = try values.decodeIfPresent([Edit].self, forKey: .undoStack) ?? []

        guard !decodedTrackKey.isEmpty,
              !decodedFingerprint.isEmpty,
              Self.normalizedDuration(decodedDuration) == decodedDuration,
              decodedLyrics.timelineFingerprint(duration: decodedDuration) == decodedFingerprint,
              let texts = Self.supportedLines(in: decodedLyrics),
              texts.contains(where: Self.isNonEmpty),
              Self.validAnchors(decodedAnchors, texts: texts, duration: decodedDuration),
              decodedUpdatedAt.timeIntervalSinceReferenceDate.isFinite,
              Self.validUndoHistory(
                  decodedUndo,
                  from: decodedAnchors,
                  texts: texts,
                  duration: decodedDuration
              )
        else { throw TapSyncProjectError.corruptProject }

        trackKey = decodedTrackKey
        baseLyricsFingerprint = decodedFingerprint
        baseLyrics = decodedLyrics
        trackDuration = decodedDuration
        anchors = decodedAnchors
        updatedAt = decodedUpdatedAt
        undoStack = decodedUndo
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(trackKey, forKey: .trackKey)
        try values.encode(baseLyricsFingerprint, forKey: .baseLyricsFingerprint)
        try values.encode(baseLyrics, forKey: .baseLyrics)
        try values.encodeIfPresent(trackDuration, forKey: .trackDuration)
        try values.encode(anchors, forKey: .anchors)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(undoStack, forKey: .undoStack)
    }

    mutating func migrateTrackKey(to key: String) {
        trackKey = key
    }

    private static func normalizedDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static func supportedLines(in lyrics: LyricsSnapshot) -> [String]? {
        switch lyrics.availability {
        case .plain:
            return lyrics.plainLines
        case .synced:
            return lyrics.lines.map(\.text)
        default:
            return nil
        }
    }

    private static func isNonEmpty(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func validAnchors(
        _ anchors: [TapSyncAnchor],
        texts: [String],
        duration: TimeInterval?
    ) -> Bool {
        var previous: TapSyncAnchor?
        for anchor in anchors {
            guard texts.indices.contains(anchor.lineIndex),
                  isNonEmpty(texts[anchor.lineIndex]),
                  anchor.playbackTime.isFinite,
                  anchor.playbackTime >= 0,
                  duration.map({ anchor.playbackTime <= $0 }) ?? true,
                  previous.map({
                      $0.lineIndex < anchor.lineIndex
                          && $0.playbackTime < anchor.playbackTime
                  }) ?? true
            else { return false }
            previous = anchor
        }
        return true
    }

    /// Validate undo entries by actually replaying them backwards. This avoids
    /// accepting a individually plausible previous anchor that would cross one
    /// of its neighbors when restored.
    private static func validUndoHistory(
        _ edits: [Edit],
        from currentAnchors: [TapSyncAnchor],
        texts: [String],
        duration: TimeInterval?
    ) -> Bool {
        var simulated = currentAnchors
        for edit in edits.reversed() {
            guard texts.indices.contains(edit.lineIndex),
                  isNonEmpty(texts[edit.lineIndex])
            else { return false }
            simulated.removeAll { $0.lineIndex == edit.lineIndex }
            if let previous = edit.previousAnchor {
                guard previous.lineIndex == edit.lineIndex else { return false }
                simulated.append(previous)
                simulated.sort { $0.lineIndex < $1.lineIndex }
            }
            guard validAnchors(simulated, texts: texts, duration: duration) else {
                return false
            }
        }
        return true
    }
}
