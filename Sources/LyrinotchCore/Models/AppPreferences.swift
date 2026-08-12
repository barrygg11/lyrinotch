import Foundation

/// Which display should host the notch lyrics overlay.
public enum ScreenPlacement: Codable, Sendable, Equatable, Hashable {
    /// Follow the screen under the mouse pointer.
    case mouseCursor
    /// Pin to a specific display (`CGDirectDisplayID` + last-known localized name).
    case specific(displayID: UInt32, displayName: String)
    /// Legacy: always main menu-bar display (still resolved at runtime).
    case mainDisplay
    /// Legacy: prefer notched / built-in display when present.
    case preferNotched

    public static let `default`: ScreenPlacement = .preferNotched

    private enum CodingKeys: String, CodingKey {
        case type, displayID, displayName
    }

    private enum Kind: String, Codable {
        case mouseCursor
        case specific
        case mainDisplay
        case preferNotched
    }

    public init(from decoder: Decoder) throws {
        // Legacy single-string encoding from older builds.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self)
        {
            switch raw {
            case "mouseCursor": self = .mouseCursor
            case "mainDisplay": self = .mainDisplay
            case "preferNotched": self = .preferNotched
            default:
                self = .preferNotched
            }
            return
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .mouseCursor:
            self = .mouseCursor
        case .mainDisplay:
            self = .mainDisplay
        case .preferNotched:
            self = .preferNotched
        case .specific:
            let id = try c.decode(UInt32.self, forKey: .displayID)
            let name = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
            self = .specific(displayID: id, displayName: name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mouseCursor:
            try c.encode(Kind.mouseCursor, forKey: .type)
        case .mainDisplay:
            try c.encode(Kind.mainDisplay, forKey: .type)
        case .preferNotched:
            try c.encode(Kind.preferNotched, forKey: .type)
        case .specific(let id, let name):
            try c.encode(Kind.specific, forKey: .type)
            try c.encode(id, forKey: .displayID)
            try c.encode(name, forKey: .displayName)
        }
    }
}

/// Persisted user settings for the Lyrinotch agent.
public struct AppPreferences: Codable, Sendable, Equatable {
    public var isOverlayVisible: Bool
    public var appearance: OverlayAppearance
    public var screenPlacement: ScreenPlacement
    /// Extra points to push the panel downward from the top chrome (can be negative).
    public var verticalOffset: Double
    /// Desired launch-at-login state (actual status depends on SMAppService).
    public var launchAtLogin: Bool
    /// Register global hotkeys.
    public var hotKeyEnabled: Bool
    /// Keep the island expanded (title + progress) until collapsed again.
    public var preferExpanded: Bool
    /// Briefly expand when the track changes.
    public var expandOnTrackChange: Bool
    /// UI language (Settings → System).
    public var preferredLanguage: AppLanguage
    /// Convert Simplified Chinese lyrics / status to Traditional for display.
    public var displayTraditionalChinese: Bool
    /// Global lyrics timeline offset in seconds (positive = show later lines sooner).
    /// Applied as `activePosition = playbackPosition + lyricOffsetSeconds (+ per-track auto)`.
    public var lyricOffsetSeconds: Double
    /// Listen on the mic and auto-calibrate a per-track lyric offset (speakers work best).
    public var autoCalibrateLyricOffset: Bool
    /// Hide the island while the target display looks fullscreen-occupied.
    public var hideInFullscreen: Bool
    /// Tint primary lyrics with a color sampled from album art.
    public var lyricColorFromArtwork: Bool
    /// Extra width for the collapsed / expanded island (points). 0 = default.
    public var islandExtraWidth: Double
    /// Multi-source lyrics order.
    public var lyricsSourcePreference: LyricsSourcePreference
    /// Show optional translation under the primary lyric line.
    public var showTranslation: Bool
    /// BCP-47 target for MyMemory translation (e.g. zh-TW, en, ja).
    public var translationTargetLanguage: String
    /// Preferred desktop player when both have a loaded track.
    public var playerSelectionPreference: PlayerSelectionPreference

    public init(
        isOverlayVisible: Bool = true,
        appearance: OverlayAppearance = .default,
        /// Prefer the notched built-in panel when present (M-series MacBook).
        screenPlacement: ScreenPlacement = .preferNotched,
        /// Keep near 0 so the island stays welded to the camera housing.
        verticalOffset: Double = 0,
        launchAtLogin: Bool = false,
        hotKeyEnabled: Bool = true,
        preferExpanded: Bool = false,
        expandOnTrackChange: Bool = true,
        preferredLanguage: AppLanguage = .system,
        displayTraditionalChinese: Bool = true,
        lyricOffsetSeconds: Double = 0,
        autoCalibrateLyricOffset: Bool = false,
        hideInFullscreen: Bool = true,
        lyricColorFromArtwork: Bool = true,
        islandExtraWidth: Double = 0,
        lyricsSourcePreference: LyricsSourcePreference = .lrclibOnly,
        showTranslation: Bool = false,
        translationTargetLanguage: String = "zh-TW",
        playerSelectionPreference: PlayerSelectionPreference = .automatic
    ) {
        self.isOverlayVisible = isOverlayVisible
        self.appearance = appearance
        self.screenPlacement = screenPlacement
        self.verticalOffset = min(40, max(-20, verticalOffset))
        self.launchAtLogin = launchAtLogin
        self.hotKeyEnabled = hotKeyEnabled
        self.preferExpanded = preferExpanded
        self.expandOnTrackChange = expandOnTrackChange
        self.preferredLanguage = preferredLanguage
        self.displayTraditionalChinese = displayTraditionalChinese
        self.lyricOffsetSeconds = min(5, max(-5, lyricOffsetSeconds))
        self.autoCalibrateLyricOffset = autoCalibrateLyricOffset
        self.hideInFullscreen = hideInFullscreen
        self.lyricColorFromArtwork = lyricColorFromArtwork
        self.islandExtraWidth = min(120, max(0, islandExtraWidth))
        self.lyricsSourcePreference = lyricsSourcePreference
        self.showTranslation = showTranslation
        self.translationTargetLanguage = translationTargetLanguage
        self.playerSelectionPreference = playerSelectionPreference
    }

    public static let `default` = AppPreferences()

    enum CodingKeys: String, CodingKey {
        case isOverlayVisible, appearance, screenPlacement, verticalOffset
        case launchAtLogin, hotKeyEnabled, preferExpanded, expandOnTrackChange
        case preferredLanguage
        case displayTraditionalChinese, lyricOffsetSeconds, autoCalibrateLyricOffset
        case hideInFullscreen, lyricColorFromArtwork, islandExtraWidth
        case lyricsSourcePreference, showTranslation, translationTargetLanguage
        case playerSelectionPreference
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isOverlayVisible: try c.decodeIfPresent(Bool.self, forKey: .isOverlayVisible) ?? true,
            appearance: try c.decodeIfPresent(OverlayAppearance.self, forKey: .appearance) ?? .default,
            screenPlacement: try c.decodeIfPresent(ScreenPlacement.self, forKey: .screenPlacement) ?? .preferNotched,
            verticalOffset: try c.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? 0,
            launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            hotKeyEnabled: try c.decodeIfPresent(Bool.self, forKey: .hotKeyEnabled) ?? true,
            preferExpanded: try c.decodeIfPresent(Bool.self, forKey: .preferExpanded) ?? false,
            expandOnTrackChange: try c.decodeIfPresent(Bool.self, forKey: .expandOnTrackChange) ?? true,
            preferredLanguage: try c.decodeIfPresent(AppLanguage.self, forKey: .preferredLanguage)
                ?? .system,
            displayTraditionalChinese: try c.decodeIfPresent(Bool.self, forKey: .displayTraditionalChinese) ?? true,
            lyricOffsetSeconds: try c.decodeIfPresent(Double.self, forKey: .lyricOffsetSeconds) ?? 0,
            autoCalibrateLyricOffset: try c.decodeIfPresent(Bool.self, forKey: .autoCalibrateLyricOffset) ?? false,
            hideInFullscreen: try c.decodeIfPresent(Bool.self, forKey: .hideInFullscreen) ?? true,
            lyricColorFromArtwork: try c.decodeIfPresent(Bool.self, forKey: .lyricColorFromArtwork) ?? true,
            islandExtraWidth: try c.decodeIfPresent(Double.self, forKey: .islandExtraWidth) ?? 0,
            lyricsSourcePreference: try c.decodeIfPresent(
                LyricsSourcePreference.self,
                forKey: .lyricsSourcePreference
            ) ?? .lrclibOnly,
            showTranslation: try c.decodeIfPresent(Bool.self, forKey: .showTranslation) ?? false,
            translationTargetLanguage: try c.decodeIfPresent(String.self, forKey: .translationTargetLanguage) ?? "zh-TW",
            playerSelectionPreference: try c.decodeIfPresent(
                PlayerSelectionPreference.self,
                forKey: .playerSelectionPreference
            ) ?? .automatic
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isOverlayVisible, forKey: .isOverlayVisible)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(screenPlacement, forKey: .screenPlacement)
        try c.encode(verticalOffset, forKey: .verticalOffset)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(hotKeyEnabled, forKey: .hotKeyEnabled)
        try c.encode(preferExpanded, forKey: .preferExpanded)
        try c.encode(expandOnTrackChange, forKey: .expandOnTrackChange)
        try c.encode(preferredLanguage, forKey: .preferredLanguage)
        try c.encode(displayTraditionalChinese, forKey: .displayTraditionalChinese)
        try c.encode(lyricOffsetSeconds, forKey: .lyricOffsetSeconds)
        try c.encode(autoCalibrateLyricOffset, forKey: .autoCalibrateLyricOffset)
        try c.encode(hideInFullscreen, forKey: .hideInFullscreen)
        try c.encode(lyricColorFromArtwork, forKey: .lyricColorFromArtwork)
        try c.encode(islandExtraWidth, forKey: .islandExtraWidth)
        try c.encode(lyricsSourcePreference, forKey: .lyricsSourcePreference)
        try c.encode(showTranslation, forKey: .showTranslation)
        try c.encode(translationTargetLanguage, forKey: .translationTargetLanguage)
        try c.encode(playerSelectionPreference, forKey: .playerSelectionPreference)
    }
}

extension OverlayAppearance: Codable {
    enum CodingKeys: String, CodingKey {
        case opacity, fontSize, showTrackTitle, showAdjacentLines, clickThrough
        case liquidGlassOnNotch, liquidGlassOnFloating, glassVariant
        /// Legacy single switch (v6–v7).
        case surfaceStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Migrate old `surfaceStyle == .liquidGlass` → both targets on.
        let legacyStyle = try c.decodeIfPresent(OverlaySurfaceStyle.self, forKey: .surfaceStyle)
        let legacyAllOn = legacyStyle == .liquidGlass

        self.init(
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.88,
            fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 15,
            showTrackTitle: try c.decodeIfPresent(Bool.self, forKey: .showTrackTitle) ?? false,
            showAdjacentLines: try c.decodeIfPresent(Bool.self, forKey: .showAdjacentLines) ?? false,
            clickThrough: try c.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? true,
            liquidGlassOnNotch: try c.decodeIfPresent(Bool.self, forKey: .liquidGlassOnNotch) ?? legacyAllOn,
            liquidGlassOnFloating: try c.decodeIfPresent(Bool.self, forKey: .liquidGlassOnFloating) ?? legacyAllOn,
            glassVariant: try c.decodeIfPresent(LiquidGlassVariant.self, forKey: .glassVariant) ?? .tinted
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(showTrackTitle, forKey: .showTrackTitle)
        try c.encode(showAdjacentLines, forKey: .showAdjacentLines)
        try c.encode(clickThrough, forKey: .clickThrough)
        try c.encode(liquidGlassOnNotch, forKey: .liquidGlassOnNotch)
        try c.encode(liquidGlassOnFloating, forKey: .liquidGlassOnFloating)
        try c.encode(glassVariant, forKey: .glassVariant)
    }
}
