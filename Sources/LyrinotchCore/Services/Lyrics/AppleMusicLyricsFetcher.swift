import Foundation

public enum AppleMusicLyricsError: Error, LocalizedError, Sendable, Equatable {
    case script(String)
    case malformedPayload

    public var errorDescription: String? {
        switch self {
        case .script(let message): return "Music lyrics: \(message)"
        case .malformedPayload: return "Music returned an invalid lyrics payload"
        }
    }
}

/// Reads plain lyrics from Music.app (`lyrics of current track`) when available.
public struct AppleMusicLyricsFetcher: LyricsFetching {
    private let executor: any AppleScriptExecuting

    public init(executor: any AppleScriptExecuting = ProcessAppleScriptExecutor()) {
        self.executor = executor
    }

    public func fetch(for track: Track) async throws -> LyricsSnapshot {
        let script = """
        set sep to character id 30
        try
          tell application "Music"
            if not (exists current track) then return "NOT_FOUND"
            set t to current track
            set tid to ""
            try
              set tid to (persistent ID of t as text)
            end try
            if tid is "" then
              try
                set tid to (database ID of t as text)
              end try
            end if
            set lyr to lyrics of t
            if lyr is missing value then return "NOT_FOUND"
            return "OK" & sep & tid & sep & (name of t as text) & sep & (artist of t as text) & sep & (duration of t as text) & sep & (lyr as text)
          end tell
        on error errMsg
          return "ERROR" & sep & errMsg
        end try
        """
        let raw = try await executor.run(script: script)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "NOT_FOUND" else {
            return LyricsSnapshot(
                availability: .notFound,
                source: "apple-music",
                detail: "No lyrics on current Music track"
            )
        }

        let parts = raw.split(
            separator: "\u{001e}",
            maxSplits: 5,
            omittingEmptySubsequences: false
        ).map(String.init)
        if parts.first == "ERROR" {
            throw AppleMusicLyricsError.script(parts.dropFirst().joined(separator: " "))
        }
        guard parts.count == 6, parts[0] == "OK" else {
            throw AppleMusicLyricsError.malformedPayload
        }

        let returnedID = parts[1]
        let returnedTitle = parts[2]
        let returnedArtist = parts[3]
        let returnedDuration = LyricsInputLimits.validDuration(
            Double(parts[4].replacingOccurrences(of: ",", with: "."))
        )
        if let requestedID = track.id,
           !requestedID.isEmpty,
           !returnedID.isEmpty,
           requestedID != returnedID
        {
            return LyricsSnapshot(
                availability: .notFound,
                source: "apple-music",
                detail: "Current Music track changed before lyrics were read"
            )
        }
        let identity = TrackQueryNormalizer.identityConfidence(
            wantArtist: track.artist,
            wantTitle: track.name,
            gotArtist: returnedArtist,
            gotTitle: returnedTitle,
            wantDuration: track.duration,
            gotDuration: returnedDuration
        )
        guard identity >= TrackQueryNormalizer.minimumAcceptIdentity else {
            return LyricsSnapshot(
                availability: .notFound,
                source: "apple-music",
                detail: "Current Music track no longer matches the request"
            )
        }

        let text = parts[5].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return LyricsSnapshot(availability: .notFound, source: "apple-music")
        }
        guard LyricsInputLimits.textFitsNetworkLimits(text) else {
            return LyricsSnapshot(availability: .notFound, source: "apple-music")
        }
        let matchedTrack = LyricsMatchMetadata(
            title: returnedTitle,
            artist: returnedArtist,
            duration: returnedDuration,
            providerID: returnedID.isEmpty ? nil : returnedID
        )
        // Music.app usually returns plain text (sometimes with blank lines).
        let plainLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // If it happens to be LRC-shaped, parse as synced.
        if text.contains("["), text.contains(":") {
            let lines = LRCParser.parse(
                text,
                maximumLines: LyricsInputLimits.maximumNetworkTimedLines + 1
            )
            guard lines.count <= LyricsInputLimits.maximumNetworkTimedLines else {
                return LyricsSnapshot(availability: .notFound, source: "apple-music")
            }
            if lines.count >= 2 {
                return LyricsSnapshot(
                    availability: .synced,
                    lines: TrackQueryNormalizer.preferringJapaneseLines(lines),
                    source: "apple-music",
                    detail: "Music.app LRC",
                    matchedTrack: matchedTrack
                )
            }
        }
        guard !plainLines.isEmpty else {
            return LyricsSnapshot(availability: .notFound, source: "apple-music")
        }
        return LyricsSnapshot(
            availability: .plain,
            plainLines: TrackQueryNormalizer.preferringJapanesePlainLines(plainLines),
            source: "apple-music",
            detail: "Music.app plain",
            matchedTrack: matchedTrack
        )
    }
}
