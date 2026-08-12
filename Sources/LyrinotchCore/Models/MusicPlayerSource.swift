import Foundation

/// Desktop music player that Lyrinotch can read via AppleScript.
public enum MusicPlayerSource: String, Sendable, Hashable, Codable, CaseIterable {
    case spotify
    case appleMusic

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }

    /// Compact badge for the expanded island header.
    public var shortBadge: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        }
    }

    var other: MusicPlayerSource {
        switch self {
        case .spotify: return .appleMusic
        case .appleMusic: return .spotify
        }
    }
}

/// User preference used when both supported desktop players have a loaded track.
public enum PlayerSelectionPreference: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case automatic
    case spotify
    case appleMusic

    public var id: Self { self }

    public var preferredSource: MusicPlayerSource? {
        switch self {
        case .automatic: return nil
        case .spotify: return .spotify
        case .appleMusic: return .appleMusic
        }
    }

    public var displayNameKey: String {
        switch self {
        case .automatic: return "player.preference.automatic"
        case .spotify: return "player.preference.spotify"
        case .appleMusic: return "player.preference.apple_music"
        }
    }
}
