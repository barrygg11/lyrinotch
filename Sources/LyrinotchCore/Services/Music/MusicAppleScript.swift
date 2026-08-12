import Foundation

/// AppleScript payloads for the Music.app desktop player (formerly iTunes).
public enum MusicAppleScript {
    /// Same unit-separator as Spotify payloads for a shared parser shape.
    public static let fieldSeparator = "\u{001e}"

    /// Now-playing query. Duration from Music is in **seconds** (not ms).
    public static let nowPlayingScript: String = """
    use framework "Foundation"
    set sep to character id 30
    if application "Music" is running then
      tell application "Music"
        if player state is stopped then
          return "STOPPED"
        end if
        try
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
          set sampledPosition to player position
          set sampleDate to current application's NSDate's |date|()
          set positionSampledAt to sampleDate's timeIntervalSince1970()
          return "OK" & sep & (player state as text) & sep & tid & sep & (name of t as text) & sep & (artist of t as text) & sep & (album of t as text) & sep & (duration of t as text) & sep & (sampledPosition as text) & sep & (positionSampledAt as text)
        on error errMsg
          return "ERROR" & sep & errMsg
        end try
      end tell
    else
      return "NOT_RUNNING"
    end if
    """

    public static let playPauseScript = """
    if application "Music" is running then
      tell application "Music" to playpause
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    public static let nextTrackScript = """
    if application "Music" is running then
      tell application "Music" to next track
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    public static let previousTrackScript = """
    if application "Music" is running then
      tell application "Music" to previous track
      return "OK"
    end if
    return "NOT_RUNNING"
    """

    /// Seek to `seconds`.
    public static func seekScript(seconds: TimeInterval) -> String {
        let value = String(format: "%.3f", max(0, seconds))
        return """
        if application "Music" is running then
          tell application "Music"
            set player position to \(value)
          end tell
          return "OK"
        end if
        return "NOT_RUNNING"
        """
    }

    /// Writes current track artwork to a temp file; returns POSIX path or empty.
    public static let artworkFileScript = """
    set outPath to (POSIX path of (path to temporary items folder)) & "lyrinotch-music-art-" & (do shell script "uuidgen") & ".img"
    if application "Music" is running then
      tell application "Music"
        try
          if player state is stopped then return ""
          set arts to artworks of current track
          if (count of arts) is 0 then return ""
          set rawData to raw data of item 1 of arts
          set fRef to open for access (POSIX file outPath) with write permission
          set eof of fRef to 0
          write rawData to fRef
          close access fRef
          return outPath
        on error
          try
            close access (POSIX file outPath)
          end try
          try
            do shell script "/bin/rm -f " & quoted form of outPath
          end try
          return ""
        end try
      end tell
    end if
    return ""
    """
}
