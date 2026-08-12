import Foundation

/// Parses AppleScript stdout from `MusicAppleScript.nowPlayingScript`.
public enum MusicNowPlayingParser {
    /// - Parameter raw: Trimmed stdout from osascript.
    public static func parse(_ raw: String) -> NowPlayingSnapshot {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return NowPlayingSnapshot(
                availability: .error,
                detail: "Empty Music AppleScript output",
                source: .appleMusic
            )
        }

        if text == "NOT_RUNNING" {
            return NowPlayingSnapshot(
                availability: .playerNotRunning,
                detail: "Music is not running",
                source: .appleMusic
            )
        }

        if text == "STOPPED" {
            return NowPlayingSnapshot(
                availability: .noTrack,
                detail: "Music has no track loaded",
                source: .appleMusic
            )
        }

        let sep = MusicAppleScript.fieldSeparator
        let parts = text.components(separatedBy: sep)

        if parts.first == "ERROR" {
            let message = parts.dropFirst().joined(separator: sep)
            return NowPlayingSnapshot(
                availability: .error,
                detail: message.isEmpty ? "Music AppleScript error" : message,
                source: .appleMusic
            )
        }

        // OK | state | id | name | artist | album | durationSec | positionSec | sampledAtEpoch
        // The timestamp was added after the original payload, so eight fields
        // remain valid for compatibility.
        guard parts.count >= 8, parts[0] == "OK" else {
            return NowPlayingSnapshot(
                availability: .error,
                detail: "Unrecognized Music payload: \(text.prefix(120))",
                source: .appleMusic
            )
        }

        let state = parts[1].lowercased()
        let id = parts[2]
        let name = parts[3]
        let artist = parts[4]
        let album = parts[5]
        // Music.app reports duration in seconds (Spotify uses milliseconds).
        let durationSec = Double(parts[6].replacingOccurrences(of: ",", with: "."))
        let positionSec = Double(parts[7].replacingOccurrences(of: ",", with: "."))
        let positionSampledAt: Date? = {
            guard parts.count >= 9 else { return nil }
            let value = parts[8].replacingOccurrences(of: ",", with: ".")
            guard let epoch = TimeInterval(value), epoch.isFinite, epoch > 0 else { return nil }
            return Date(timeIntervalSince1970: epoch)
        }()

        let isPlaying = (state == "playing")
        let track = Track(
            id: id.isEmpty ? nil : id,
            name: name,
            artist: artist,
            album: album.isEmpty ? nil : album,
            duration: durationSec,
            position: positionSec,
            isPlaying: isPlaying,
            positionSampledAt: positionSampledAt
        )

        return NowPlayingSnapshot(
            availability: .ready,
            track: track,
            detail: state,
            source: .appleMusic
        )
    }
}
