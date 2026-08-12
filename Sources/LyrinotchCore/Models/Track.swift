import Foundation

/// A track currently (or recently) playing in a supported desktop player.
public struct Track: Equatable, Sendable {
    public var id: String?
    public var name: String
    public var artist: String
    public var album: String?
    /// Total duration in seconds.
    public var duration: TimeInterval?
    /// Playback position in seconds.
    public var position: TimeInterval?
    public var isPlaying: Bool
    /// Player catalog that supplied `id`. IDs are only unique in this namespace.
    public var source: MusicPlayerSource?
    /// Wall-clock time when `position` was read from the player.
    ///
    /// This is intentionally carried with the position instead of being filled
    /// in by consumers: a combined Spotify/Music query can finish long after the
    /// selected player actually supplied its playhead.
    public var positionSampledAt: Date?

    public init(
        id: String?,
        name: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        position: TimeInterval?,
        isPlaying: Bool,
        positionSampledAt: Date? = nil,
        source: MusicPlayerSource? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.isPlaying = isPlaying
        self.positionSampledAt = positionSampledAt
        self.source = source
    }

    public var displayTitle: String {
        if name.isEmpty && artist.isEmpty {
            return L10n.t("track.not_playing")
        }
        if artist.isEmpty {
            return name
        }
        if name.isEmpty {
            return artist
        }
        return "\(artist) — \(name)"
    }

    public static let empty = Track(
        id: nil,
        name: "",
        artist: "",
        album: nil,
        duration: nil,
        position: nil,
        isPlaying: false,
        positionSampledAt: nil,
        source: nil
    )
}
