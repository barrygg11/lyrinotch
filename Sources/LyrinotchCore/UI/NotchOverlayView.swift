import AppKit
import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Lyrics overlay: notch-island on notched MacBooks, floating HUD elsewhere.
public struct NotchOverlayView: View {
    public var track: Track
    public var lines: [LyricLine]
    public var position: TimeInterval
    public var lyricsAvailability: LyricsAvailability
    public var appearance: OverlayAppearance
    public var statusMessage: String?
    public var islandMode: IslandMode
    public var deviceNotchSize: CGSize
    public var hasPhysicalNotch: Bool
    public var presentationStyle: OverlayPresentationStyle
    /// 「維持展開」— hide collapse chrome so the lock cannot be dismissed by X.
    public var expandLocked: Bool
    public var playerSource: MusicPlayerSource?
    public var artwork: NSImage?
    /// Optional accent for primary lyrics (from album art).
    public var lyricAccent: Color?
    /// Extra width (pt) added to collapsed / expanded island.
    public var islandExtraWidth: CGFloat
    /// Optional translation under the primary line.
    public var translationText: String?
    /// Fetch in progress (show loading placeholder).
    public var isLoadingLyrics: Bool
    /// Compact status for sync / calibration (expanded island).
    public var syncStatusText: String?
    /// Per-track offset seconds currently applied (for chip label).
    public var trackOffsetSeconds: Double
    /// Whether a saved automatic/manual per-track correction exists, including 0.0s.
    public var hasTrackOffset: Bool

    public var onToggleExpand: (() -> Void)?
    public var onPlayPause: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((TimeInterval) -> Void)?
    public var onRefreshLyrics: (() -> Void)?
    /// Per-track nudge: positive = lyrics late (show later lines sooner).
    public var onNudgeTrackOffset: ((Double) -> Void)?
    public var onResetTrackOffset: (() -> Void)?

    @State private var scrubFraction: Double?
    @State private var isScrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        track: Track,
        lines: [LyricLine],
        position: TimeInterval,
        lyricsAvailability: LyricsAvailability = .synced,
        appearance: OverlayAppearance = .default,
        statusMessage: String? = nil,
        islandMode: IslandMode = .collapsed,
        deviceNotchSize: CGSize = CGSize(width: 180, height: 32),
        hasPhysicalNotch: Bool = true,
        presentationStyle: OverlayPresentationStyle = .notchIsland,
        expandLocked: Bool = false,
        playerSource: MusicPlayerSource? = nil,
        artwork: NSImage? = nil,
        lyricAccent: Color? = nil,
        islandExtraWidth: CGFloat = 0,
        translationText: String? = nil,
        isLoadingLyrics: Bool = false,
        syncStatusText: String? = nil,
        trackOffsetSeconds: Double = 0,
        hasTrackOffset: Bool = false,
        onToggleExpand: (() -> Void)? = nil,
        onPlayPause: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        onPrevious: (() -> Void)? = nil,
        onSeek: ((TimeInterval) -> Void)? = nil,
        onRefreshLyrics: (() -> Void)? = nil,
        onNudgeTrackOffset: ((Double) -> Void)? = nil,
        onResetTrackOffset: (() -> Void)? = nil
    ) {
        self.track = track
        self.lines = lines
        self.position = position
        self.lyricsAvailability = lyricsAvailability
        self.appearance = appearance
        self.statusMessage = statusMessage
        self.islandMode = islandMode
        self.deviceNotchSize = deviceNotchSize
        self.hasPhysicalNotch = hasPhysicalNotch
        self.presentationStyle = presentationStyle
        self.expandLocked = expandLocked
        self.playerSource = playerSource
        self.artwork = artwork
        self.lyricAccent = lyricAccent
        self.islandExtraWidth = max(0, islandExtraWidth)
        self.translationText = translationText
        self.isLoadingLyrics = isLoadingLyrics
        self.syncStatusText = syncStatusText
        self.trackOffsetSeconds = trackOffsetSeconds
        self.hasTrackOffset = hasTrackOffset
        self.onToggleExpand = onToggleExpand
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        self.onRefreshLyrics = onRefreshLyrics
        self.onNudgeTrackOffset = onNudgeTrackOffset
        self.onResetTrackOffset = onResetTrackOffset
    }

    private var isExpanded: Bool { islandMode == .expanded }
    private var isNotch: Bool { presentationStyle == .notchIsland }

    /// Dynamic Island–style spring (matches reference screen recording silkiness).
    /// Slight overshoot, settles cleanly — not snappy, not mushy.
    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
    }

    /// Content fade slightly lagging the shell for a layered feel.
    private var contentSpring: Animation? {
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86, blendDuration: 0)
    }

    /// Lyric line changes only — soft enough to read, quick enough for dense LRC.
    private var lyricSpring: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
    }

    private var accentAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.25)
    }

    /// Incoming text starts fully visible at its timestamp. Motion may continue,
    /// but readability must not wait for an opacity animation to finish.
    private var lyricLineTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 6)
                .combined(with: .scale(scale: 0.96)),
            removal: .opacity
                .combined(with: .offset(y: -8))
                .combined(with: .scale(scale: 1.02))
        )
    }

    /// Adjacent lines shift more subtly so the stack feels continuous.
    private var adjacentLineTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 4),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }

    private var collapsedLineTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .offset(y: 4),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }

    public var body: some View {
        Group {
            if isNotch {
                notchIslandChrome
            } else {
                floatingHUDChrome
            }
        }
        .animation(spring, value: islandMode)
        .animation(spring, value: isExpanded)
        .animation(lyricSpring, value: track.isPlaying)
        .animation(lyricSpring, value: primaryLineIdentity)
        .preferredColorScheme(.dark)
    }

    // MARK: - Notch island (MacBook with camera housing)

    private var closedNotchWidth: CGFloat {
        IslandVisualGeometry.closedNotchWidth(deviceNotch: deviceNotchSize)
    }
    /// Hardware camera strip height — top band of the welded island.
    private var closedNotchHeight: CGFloat {
        IslandVisualGeometry.closedNotchHeight(deviceNotch: deviceNotchSize)
    }

    /// Lyric lip hanging under the camera housing (collapsed notch).
    private var collapsedLyricLipHeight: CGFloat {
        IslandVisualGeometry.collapsedLyricLipHeight
    }

    /// Floating Live Activity capsule height (non-notch only).
    private var mediaCapsuleHeight: CGFloat {
        IslandVisualGeometry.mediaCapsuleHeight
    }

    private var showLeadingActivity: Bool {
        !track.name.isEmpty
    }

    /// Album art in the right wing beside the camera housing.
    private var notchWingArtSize: CGFloat {
        IslandVisualGeometry.notchWingArtSize(deviceNotch: deviceNotchSize)
    }

    /// Left / right ear width outside the physical camera housing.
    private var notchWingWidth: CGFloat {
        IslandVisualGeometry.notchWingWidth(deviceNotch: deviceNotchSize)
    }

    /// Collapsed island width: camera + left EQ wing + right art wing.
    /// Lyric lip below can be slightly wider, but chrome follows this.
    private var closedTotalWidth: CGFloat {
        if isNotch {
            return IslandVisualGeometry.closedNotchTotalWidth(
                deviceNotch: deviceNotchSize,
                islandExtraWidth: islandExtraWidth
            )
        }
        let chrome: CGFloat = 30 + 10 + 10 + 20 + 28
        let needed = collapsedTextSize.width + chrome + islandExtraWidth
        return min(520, max(260, needed))
    }

    private var openedWidth: CGFloat {
        IslandVisualGeometry.openedNotchWidth(
            deviceNotch: deviceNotchSize,
            islandExtraWidth: islandExtraWidth
        )
    }

    private var primaryLyricColor: Color {
        lyricAccent ?? Color.white.opacity(0.96)
    }

    // MARK: Collapsed typography

    private var collapsedBaseFontSize: CGFloat {
        max(11, min(15, CGFloat(appearance.fontSize) * 0.72))
    }

    private var collapsedFittedFontSize: CGFloat {
        collapsedFit.fontSize
    }

    private var collapsedTextSize: CGSize {
        collapsedFit.size
    }

    /// Lyric width budget — under the notch lip (not between art/EQ).
    private var collapsedMaxTextWidth: CGFloat {
        if isNotch {
            return min(420, max(closedTotalWidth - 16, closedNotchWidth + 40))
        }
        return 320
    }

    private var collapsedFit: (fontSize: CGFloat, size: CGSize) {
        let text = collapsedLabel
        guard !text.isEmpty else {
            return (collapsedBaseFontSize, .zero)
        }
        let maxTextWidth = collapsedMaxTextWidth
        var fontSize = collapsedBaseFontSize
        let minFont: CGFloat = 10

        var size = measureCollapsedText(text, fontSize: fontSize, maxWidth: maxTextWidth, lines: 1)
        while size.width > maxTextWidth, fontSize > minFont {
            fontSize -= 0.5
            size = measureCollapsedText(text, fontSize: fontSize, maxWidth: maxTextWidth, lines: 1)
        }
        size.width = min(maxTextWidth, size.width)
        return (fontSize, size)
    }

    private func measureCollapsedText(
        _ text: String,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        lines: Int
    ) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if lines <= 1 {
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: fontSize * 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            return CGSize(width: ceil(rect.width), height: ceil(rect.height))
        }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: fontSize * 3.2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return CGSize(width: ceil(min(maxWidth, rect.width)), height: ceil(rect.height))
    }

    private var topRadius: CGFloat { isExpanded ? 12 : 6 }
    private var bottomRadius: CGFloat { isExpanded ? 28 : 16 }

    private var notchShape: NotchShape {
        NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    private var islandWidth: CGFloat {
        isExpanded ? openedWidth : closedTotalWidth
    }

    /// Expanded body budget (title + lyrics ± adjacent + scrubber with end times + transport).
    /// Must be tall enough — a too-small fixed height + `.clipped()` stacks lyrics on the progress bar.
    private var expandedBodyHeight: CGFloat {
        IslandVisualGeometry.expandedBodyHeight(
            showAdjacentLines: appearance.showAdjacentLines,
            hasTranslation: hasVisibleTranslation
        )
    }

    private var hasVisibleTranslation: Bool {
        translationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Expanded notch uses Liquid Glass on the drop-down only.
    private var notchUsesLiquidGlass: Bool {
        appearance.usesLiquidGlass(for: .notchIsland) && isExpanded
    }

    private var notchIslandChrome: some View {
        ZStack(alignment: .top) {
            // Continuous morph (reference recording style):
            // one shell springs width/height; content fades via opacity + clipped height.
            // No if/else insert/remove — that causes the janky cut in the old build.
            VStack(spacing: 0) {
                // Top band always present (wings ↔ quiet camera cap).
                ZStack {
                    notchWingsRow
                        .opacity(isExpanded ? 0 : 1)
                    notchCapRow
                        .opacity(isExpanded ? 1 : 0)
                }
                .frame(height: closedNotchHeight)

                // Collapsed lyric lip — height springs to 0 when expanding.
                collapsedLyricLip
                    .frame(height: isExpanded ? 0 : collapsedLyricLipHeight)
                    .opacity(isExpanded ? 0 : 1)
                    .clipped()

                // Expanded body — spring open; roomy height so lyrics never overlap scrubber.
                VStack(spacing: 0) {
                    expandedTitleRow
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                    expandedContent
                }
                .frame(maxHeight: isExpanded ? expandedBodyHeight : 0, alignment: .top)
                .opacity(isExpanded ? 1 : 0)
                .clipped()
            }
            .frame(width: islandWidth, alignment: .top)
            .padding(.horizontal, isExpanded ? 8 : 0)
            .padding(.bottom, isExpanded ? 16 : 2)
            .modifier(SurfaceChrome(
                shape: notchShape,
                appearance: appearance,
                useLiquidGlass: notchUsesLiquidGlass,
                // Do NOT paint a full-width solid band here — it used to cover EQ + art.
                // Camera zone black is drawn inside the top row only (center).
                solidTopHeight: 0
            ))
            .contentShape(notchShape)
            .onTapGesture {
                if !isExpanded { onToggleExpand?() }
            }
            .animation(spring, value: isExpanded)
            .animation(spring, value: islandWidth)
            .animation(contentSpring, value: isExpanded)
            .animation(nil, value: appearance.liquidGlassOnNotch)
            .animation(nil, value: appearance.glassVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    /// Top band: EQ left · camera middle · album art right.
    private var notchWingsRow: some View {
        HStack(spacing: 0) {
            // Left wing — equalizer beside the camera.
            PlaybackActivityIndicator(
                isPlaying: track.isPlaying,
                isActive: true,
                compact: true
            )
            .frame(width: notchWingWidth, height: closedNotchHeight)

            // Physical camera zone only — solid black, not the wings.
            Color.black
                .frame(maxWidth: .infinity)
                .frame(minWidth: max(80, closedNotchWidth * 0.55))
                .frame(height: closedNotchHeight)

            // Right wing — album art (always draw a tile; placeholder if no artwork yet).
            albumArtView(size: notchWingArtSize)
                .frame(width: notchWingWidth, height: closedNotchHeight)
                // Keep art above any housing chrome / shadows.
                .zIndex(1)
        }
    }

    /// Single-line lyric hanging under the camera housing (not between the wings).
    private var collapsedLyricLip: some View {
        ZStack {
            Text(collapsedLabel)
                .font(.system(size: collapsedFittedFontSize, weight: .semibold))
                .foregroundStyle(primaryLyricColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .id(collapsedLabel)
                .transition(collapsedLineTransition)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(lyricSpring, value: collapsedLabel)
        .animation(accentAnimation, value: lyricAccent != nil)
    }

    // MARK: - Floating HUD (no notch)

    private var floatingWidth: CGFloat {
        if isExpanded {
            return IslandVisualGeometry.floatingExpandedWidth(islandExtraWidth: islandExtraWidth)
        }
        return closedTotalWidth
    }

    private var floatingHUDChrome: some View {
        VStack {
            floatingCard
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var floatingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isExpanded ? 22 : mediaCapsuleHeight / 2, style: .continuous)
    }

    private var floatingCard: some View {
        // Continuous morph for floating too (same spring language as notch).
        VStack(spacing: 0) {
            mediaLiveActivityCapsule
                .frame(height: isExpanded ? 0 : mediaCapsuleHeight)
                .opacity(isExpanded ? 0 : 1)
                .clipped()

            VStack(spacing: 10) {
                floatingExpandedHeader
                expandedContent
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isExpanded ? 14 : 0)
            // Match notch: keep room for adjacent lyrics + scrubber + transport.
            .frame(maxHeight: isExpanded ? expandedBodyHeight + 8 : 0, alignment: .top)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
        }
        .frame(width: floatingWidth)
        .modifier(SurfaceChrome(
            shape: floatingShape,
            appearance: appearance,
            useLiquidGlass: appearance.usesLiquidGlass(for: .floatingHUD),
            solidTopHeight: 0
        ))
        .contentShape(floatingShape)
        .onTapGesture {
            if !isExpanded { onToggleExpand?() }
        }
        .animation(spring, value: isExpanded)
        .animation(spring, value: floatingWidth)
        .animation(nil, value: appearance.liquidGlassOnFloating)
        .animation(nil, value: appearance.glassVariant)
    }

    private var floatingExpandedHeader: some View {
        HStack(spacing: 10) {
            albumArtView(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                if appearance.showTrackTitle {
                    Text(track.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let playerSource {
                        sourceBadge(playerSource)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 4)
            headerTrailingButtons
        }
    }

    /// Floating collapsed row: [EQ] [lyric] [album art] (chrome is on the parent card).
    private var mediaLiveActivityCapsule: some View {
        HStack(spacing: 10) {
            PlaybackActivityIndicator(
                isPlaying: track.isPlaying,
                isActive: showLeadingActivity,
                compact: true
            )
            .frame(width: 20, alignment: .leading)

            ZStack {
                Text(collapsedLabel)
                    .font(.system(size: collapsedFittedFontSize, weight: .semibold))
                    .foregroundStyle(primaryLyricColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .id(collapsedLabel)
                    .transition(collapsedLineTransition)
            }
            .animation(lyricSpring, value: collapsedLabel)

            albumArtView(size: 30)
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity)
        .frame(height: mediaCapsuleHeight)
    }

    // MARK: - Shared body pieces

    /// Expanded-only: quiet strip under the physical camera (no important text).
    private var notchCapRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: notchWingWidth, height: closedNotchHeight)

            // Match housing width so liquid glass doesn’t show under the camera.
            Color.black
                .frame(maxWidth: .infinity)
                .frame(height: closedNotchHeight)

            Color.clear
                .frame(width: notchWingWidth, height: closedNotchHeight)
        }
    }

    /// Fully visible below the camera housing when expanded.
    private var expandedTitleRow: some View {
        HStack(spacing: 10) {
            albumArtView(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                if appearance.showTrackTitle {
                    Text(track.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                HStack(spacing: 6) {
                    if let playerSource {
                        sourceBadge(playerSource)
                    }
                }
            }

            Spacer(minLength: 4)

            headerTrailingButtons
        }
    }

    @ViewBuilder
    private var headerTrailingButtons: some View {
        HStack(spacing: 4) {
            Button {
                onRefreshLyrics?()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("overlay.refresh_lyrics"))
            .accessibilityLabel(L10n.t("overlay.refresh_lyrics"))

            if !expandLocked {
                Button {
                    onToggleExpand?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.t("overlay.collapse"))
            }
        }
    }

    private func albumArtView(size: CGFloat) -> some View {
        let corner = size * 0.28
        return ZStack {
            // Always paint a visible tile so the wing never looks empty.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.14))

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.7)
        )
        // Force refresh when artwork arrives (NSImage identity can be sticky).
        .id(artwork.map { ObjectIdentifier($0) } ?? ObjectIdentifier(NSNull()))
    }

    private func sourceBadge(_ source: MusicPlayerSource) -> some View {
        Text(source.shortBadge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.1)))
    }

    private var collapsedLabel: String {
        if isLoadingLyrics { return L10n.t("status.loading_lyrics") }
        if let primaryText { return primaryText }
        // Instrumental gap / empty LRC beat: keep the pill informative, not blank.
        if isInstrumentalGap {
            if let countdown = upcomingCountdownText {
                return L10n.t("lyrics.interlude_countdown_short", countdown)
            }
            return L10n.t("lyrics.interlude_short")
        }
        if let statusMessage, !statusMessage.isEmpty { return statusMessage }
        // Overlay only shows while playing; keep label quiet if content is mid-fetch.
        return "…"
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            lyricBlock
                // Keep lyrics in a stable slot so they never collide with the scrubber.
                .frame(minHeight: appearance.showAdjacentLines ? 88 : 52, alignment: .center)

            progressScrubber

            transportBar
        }
        .padding(.horizontal, isNotch ? 18 : 10)
        .padding(.top, isNotch ? 10 : 8)
        .padding(.bottom, isNotch ? 10 : 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var lyricBlock: some View {
        if let primaryText {
            VStack(spacing: 6) {
                if appearance.showAdjacentLines {
                    adjacentLineView(text: adjacentText(offset: -1), identitySuffix: "prev")
                }

                // ZStack keeps insert/remove transitions overlapping for a crossfade slide.
                ZStack {
                    Text(primaryText)
                        .font(.system(size: appearance.fontSize * 1.08, weight: .semibold))
                        .foregroundStyle(primaryLyricColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .id(primaryLineIdentity)
                        .transition(lyricLineTransition)
                }
                // Fixed slot — no fixedSize(vertical:) which used to overflow into the scrubber.
                .frame(minHeight: appearance.fontSize * 1.5, alignment: .center)
                .animation(lyricSpring, value: primaryLineIdentity)
                .animation(accentAnimation, value: lyricAccent != nil)

                if let translationText, !translationText.isEmpty {
                    Text(translationText)
                        .font(.system(size: max(11, appearance.fontSize * 0.72), weight: .regular))
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .id(translationText)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .opacity.combined(with: .offset(y: 4))
                        )
                        .animation(lyricSpring, value: translationText)
                }

                if appearance.showAdjacentLines {
                    adjacentLineView(text: adjacentText(offset: 1), identitySuffix: "next")
                }
            }
            .frame(maxWidth: .infinity)
            .animation(lyricSpring, value: primaryLineIdentity)
        } else if isLoadingLyrics {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t("status.loading_lyrics"))
                    .font(.system(size: max(12, appearance.fontSize * 0.78), weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: appearance.showAdjacentLines ? 72 : 40)
        } else if isInstrumentalGap {
            // Calm interlude state — avoid a huge empty panel during 間奏.
            instrumentalGapBlock
        } else if let statusMessage, !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.system(size: max(12, appearance.fontSize * 0.88), weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Text("…")
                .font(.system(size: max(12, appearance.fontSize * 0.88), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
        }
    }

    /// Soft placeholder when LRC has no words at the current time (intro / 間奏 / outro).
    private var instrumentalGapBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.quarternote.3")
                .font(.system(size: max(22, appearance.fontSize * 1.35), weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .symbolEffect(.pulse, options: .repeating, isActive: track.isPlaying)

            Text(L10n.t("lyrics.interlude"))
                .font(.system(size: max(15, appearance.fontSize * 0.95), weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            if let next = upcomingNonEmptyLine {
                Text(
                    L10n.t(
                        "lyrics.next_line_countdown",
                        formatCountdown(next.secondsUntil(startingAt: position)),
                        next.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                    .font(.system(size: max(12, appearance.fontSize * 0.72), weight: .regular))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: appearance.showAdjacentLines ? 88 : 56)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: upcomingNonEmptyLine?.id)
    }

    private var transportBar: some View {
        // One dense row: transport · timing chips · status — no wide empty gutters.
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                transportButton(
                    systemName: "backward.fill",
                    label: L10n.t("overlay.previous")
                ) { onPrevious?() }
                transportButton(
                    systemName: track.isPlaying ? "pause.fill" : "play.fill",
                    label: L10n.t(track.isPlaying ? "overlay.pause" : "overlay.play"),
                    emphasized: true
                ) { onPlayPause?() }
                transportButton(
                    systemName: "forward.fill",
                    label: L10n.t("overlay.next")
                ) { onNext?() }
            }

            // Subtle divider so clusters read as one toolbar without a void.
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 22)

            // First-class sync controls — no need to open Settings mid-song.
            HStack(spacing: 6) {
                Button {
                    onNudgeTrackOffset?(-0.5)
                } label: {
                    Text(L10n.t("island.offset_fast"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("help.island_offset_fast"))

                Button {
                    onNudgeTrackOffset?(0.5)
                } label: {
                    Text(L10n.t("island.offset_slow"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(L10n.t("help.island_offset_slow"))

                if hasTrackOffset {
                    Text(
                        L10n.t(
                            "island.track_offset",
                            String(format: "%+.1fs", trackOffsetSeconds)
                        )
                    )
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))

                    Button {
                        onResetTrackOffset?()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("help.island_offset_reset"))
                    .accessibilityLabel(L10n.t("help.island_offset_reset"))
                }
            }

            Spacer(minLength: 6)

            if let syncStatusText, !syncStatusText.isEmpty {
                Text(syncStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Interactive seek bar (drag or click) with time anchors on both ends.
    private var progressScrubber: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let fraction = displayFraction
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.white.opacity(isScrubbing ? 0.9 : 0.55))
                        .frame(width: max(4, width * fraction), height: 4)
                    Circle()
                        .fill(Color.white.opacity(isScrubbing ? 1 : 0.85))
                        .frame(width: isScrubbing ? 10 : 8, height: isScrubbing ? 10 : 8)
                        .offset(x: max(0, width * fraction - (isScrubbing ? 5 : 4)))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard track.duration != nil, (track.duration ?? 0) > 0 else { return }
                            isScrubbing = true
                            let f = min(1, max(0, value.location.x / width))
                            scrubFraction = f
                        }
                        .onEnded { value in
                            guard let duration = track.duration, duration > 0 else {
                                isScrubbing = false
                                scrubFraction = nil
                                return
                            }
                            let f = min(1, max(0, value.location.x / width))
                            let seconds = duration * f
                            scrubFraction = f
                            onSeek?(seconds)
                            isScrubbing = false
                            // Let the next player poll provide the authoritative position.
                            scrubFraction = nil
                        }
                )
            }
            .frame(height: 14)

            HStack {
                Text(formatTime(displayPosition))
                Spacer(minLength: 8)
                Text(formatTime(track.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.42))
        }
        .accessibilityLabel(L10n.t("overlay.progress"))
        .accessibilityValue(progressLabel)
    }

    private var displayFraction: Double {
        if let scrubFraction { return scrubFraction }
        guard let duration = track.duration, duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }

    private var displayPosition: TimeInterval {
        if let scrubFraction, let duration = track.duration {
            return duration * scrubFraction
        }
        return position
    }

    private func transportButton(
        systemName: String,
        label: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 14 : 12, weight: .semibold))
                .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.72))
                .frame(width: emphasized ? 34 : 30, height: emphasized ? 34 : 30)
                .background(Circle().fill(Color.white.opacity(emphasized ? 0.14 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var progressLabel: String {
        "\(formatTime(displayPosition)) / \(formatTime(track.duration))"
    }

    /// Plain lyrics may carry an estimated timeline for display, but their
    /// availability must remain `.plain` so the UI never claims they are synced.
    static func supportsTimelineDisplay(_ availability: LyricsAvailability) -> Bool {
        availability == .synced || availability == .plain
    }

    private var activeIndex: Int? {
        guard Self.supportsTimelineDisplay(lyricsAvailability), !lines.isEmpty else { return nil }
        return LyricLine.activeIndex(in: lines, at: position)
    }

    private var primaryText: String? {
        if let index = activeIndex, lines.indices.contains(index) {
            let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// Stable identity for line transitions (index + text so repeats still animate).
    private var primaryLineIdentity: String {
        if let index = activeIndex, let primaryText {
            return "\(index)|\(primaryText)"
        }
        return primaryText ?? ""
    }

    @ViewBuilder
    private func adjacentLineView(text: String?, identitySuffix: String) -> some View {
        let display = text ?? " "
        ZStack {
            Text(display)
                .font(.system(size: appearance.fontSize * 0.68, weight: .regular))
                .foregroundStyle(.white.opacity(text == nil ? 0 : 0.32))
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .id("\(identitySuffix)|\(display)")
                .transition(adjacentLineTransition)
        }
        // Reserve a line so layout doesn’t jump when prev/next is missing.
        .frame(height: appearance.fontSize * 0.9)
        .animation(lyricSpring, value: display)
    }

    /// True when we have a timed lyric track but nothing to sing right now
    /// (empty LRC beat, intro, mid-song 間奏, outro before end).
    private var isInstrumentalGap: Bool {
        guard track.isPlaying else { return false }
        guard lyricsAvailability == .synced || lyricsAvailability == .plain else { return false }
        guard !lines.isEmpty else { return false }
        return primaryText == nil
    }

    /// Next non-empty lyric after the playhead (for interlude preview/countdown).
    private var upcomingNonEmptyLine: LyricLine? {
        LyricLine.nextNonEmpty(in: lines, after: position)
    }

    private var upcomingCountdownText: String? {
        guard let line = upcomingNonEmptyLine else { return nil }
        return formatCountdown(line.secondsUntil(startingAt: position))
    }

    private func adjacentText(offset: Int) -> String? {
        guard let index = activeIndex, offset != 0 else { return nil }
        let step = offset > 0 ? 1 : -1
        var i = index + step
        // Walk past empty LRC beats (common during 間奏).
        while lines.indices.contains(i) {
            let text = lines[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
            i += step
        }
        return nil
    }

    private func formatTime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}
#endif
