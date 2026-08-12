import Foundation

/// Visual size of the notch lyrics island / floating HUD.
public enum IslandMode: String, Codable, Sendable, CaseIterable, Equatable {
    /// Compact — current lyric only.
    case collapsed
    /// Expanded — title + lyric + transport.
    case expanded

    public var displayNameZH: String {
        localizedName
    }

    public var localizedName: String {
        switch self {
        case .collapsed: return L10n.t("mode.collapsed")
        case .expanded: return L10n.t("mode.expanded")
        }
    }
}

/// How the overlay attaches to the display.
public enum OverlayPresentationStyle: String, Sendable, Equatable {
    /// Welded to the MacBook camera housing (notched built-in display).
    case notchIsland
    /// Free-floating HUD below the menu bar (external / non-notch displays).
    case floatingHUD

    public var displayNameZH: String {
        localizedName
    }

    public var localizedName: String {
        switch self {
        case .notchIsland: return L10n.t("style.notch")
        case .floatingHUD: return L10n.t("style.floating")
        }
    }
}
