import Foundation

/// AppleScript that returns a unit-separator (ASCII 30) delimited payload for Spotify.
public enum SpotifyAppleScript {
    /// Field separator used in successful `OK` payloads.
    public static let fieldSeparator = "\u{001e}"

    /// Single-shot now-playing query for the Spotify desktop app.
    public static let nowPlayingScript: String = """
    use framework "Foundation"
    set sep to character id 30
    if application "Spotify" is running then
      tell application "Spotify"
        if (player state as text) is "stopped" then
          return "STOPPED"
        end if
        try
          set sampledPosition to player position
          set sampleDate to current application's NSDate's |date|()
          set positionSampledAt to sampleDate's timeIntervalSince1970()
          return "OK" & sep & (player state as text) & sep & (id of current track as text) & sep & (name of current track as text) & sep & (artist of current track as text) & sep & (album of current track as text) & sep & (duration of current track as text) & sep & (sampledPosition as text) & sep & (positionSampledAt as text)
        on error errMsg
          return "ERROR" & sep & errMsg
        end try
      end tell
    else
      return "NOT_RUNNING"
    end if
    """

    public static let playPauseScript = """
    if application "Spotify" is running then
      tell application "Spotify" to playpause
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    public static let nextTrackScript = """
    if application "Spotify" is running then
      tell application "Spotify" to next track
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    public static let previousTrackScript = """
    if application "Spotify" is running then
      tell application "Spotify" to previous track
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    /// Seek to `seconds` (player position is in seconds).
    public static func seekScript(seconds: TimeInterval) -> String {
        let value = String(format: "%.3f", max(0, seconds))
        return """
        if application "Spotify" is running then
          tell application "Spotify"
            set player position to \(value)
          end tell
          return "OK"
        end if
        return "NOT_RUNNING"
        """
    }

    /// Returns artwork URL string or empty.
    public static let artworkURLScript = """
    if application "Spotify" is running then
      tell application "Spotify"
        try
          if player state is stopped then return ""
          return artwork url of current track as text
        on error
          return ""
        end try
      end tell
    end if
    return ""
    """
}
