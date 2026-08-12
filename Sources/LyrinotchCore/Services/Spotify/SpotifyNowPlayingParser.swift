import Foundation

/// Parses AppleScript stdout from `SpotifyAppleScript.nowPlayingScript`.
public enum SpotifyNowPlayingParser {
    /// - Parameter raw: Trimmed stdout from osascript.
    public static func parse(_ raw: String) -> NowPlayingSnapshot {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return NowPlayingSnapshot(
                availability: .error,
                detail: "Empty AppleScript output",
                source: .spotify
            )
        }

        if text == "NOT_RUNNING" {
            return NowPlayingSnapshot(
                availability: .playerNotRunning,
                detail: "Spotify is not running",
                source: .spotify
            )
        }

        if text == "STOPPED" {
            return NowPlayingSnapshot(
                availability: .noTrack,
                detail: "Spotify has no track loaded",
                source: .spotify
            )
        }

        let sep = SpotifyAppleScript.fieldSeparator
        let parts = text.components(separatedBy: sep)

        if parts.first == "ERROR" {
            let message = parts.dropFirst().joined(separator: sep)
            return NowPlayingSnapshot(
                availability: .error,
                detail: message.isEmpty ? "Spotify AppleScript error" : message,
                source: .spotify
            )
        }

        // OK | state | id | name | artist | album | durationMs | positionSec | sampledAtEpoch
        // Keep accepting the legacy eight-field payload so older fixtures and
        // third-party executors continue to parse; only the timestamp is absent.
        guard parts.count >= 8, parts[0] == "OK" else {
            return NowPlayingSnapshot(
                availability: .error,
                detail: "Unrecognized AppleScript payload: \(text.prefix(120))",
                source: .spotify
            )
        }

        let state = parts[1].lowercased()
        let id = parts[2]
        let name = parts[3]
        let artist = parts[4]
        let album = parts[5]
        let durationMs = Double(parts[6].replacingOccurrences(of: ",", with: "."))
        let positionSec = Double(parts[7].replacingOccurrences(of: ",", with: "."))
        let positionSampledAt: Date? = {
            guard parts.count >= 9 else { return nil }
            let value = parts[8].replacingOccurrences(of: ",", with: ".")
            guard let epoch = TimeInterval(value), epoch.isFinite, epoch > 0 else { return nil }
            return Date(timeIntervalSince1970: epoch)
        }()

        // Spotify AppleScript reports duration in milliseconds.
        let durationSec: TimeInterval? = durationMs.map { $0 / 1000.0 }

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
            source: .spotify
        )
    }
}
