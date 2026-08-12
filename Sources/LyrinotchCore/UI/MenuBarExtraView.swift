import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Compact menu-bar dropdown — everyday controls only.
/// Full configuration lives in the separate Settings window.
public struct MenuBarExtraView: View {
    public var trackTitle: String
    public var playbackGlyph: String
    public var lyricsLabel: String
    public var islandModeLabel: String
    public var isOverlayVisible: Bool
    public var isIslandExpanded: Bool
    public var lastError: String?

    public var onToggleOverlay: () -> Void
    public var onToggleExpand: () -> Void
    public var onRefresh: () -> Void
    public var onSearchLyrics: () -> Void
    public var onOpenSettings: () -> Void
    public var onOpenAbout: () -> Void
    public var onOpenDonate: () -> Void
    public var onReportBug: () -> Void
    public var onQuit: () -> Void

    public init(
        trackTitle: String,
        playbackGlyph: String,
        lyricsLabel: String,
        islandModeLabel: String,
        isOverlayVisible: Bool,
        isIslandExpanded: Bool,
        lastError: String?,
        onToggleOverlay: @escaping () -> Void,
        onToggleExpand: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSearchLyrics: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void = {},
        onOpenDonate: @escaping () -> Void = {},
        onReportBug: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        self.trackTitle = trackTitle
        self.playbackGlyph = playbackGlyph
        self.lyricsLabel = lyricsLabel
        self.islandModeLabel = islandModeLabel
        self.isOverlayVisible = isOverlayVisible
        self.isIslandExpanded = isIslandExpanded
        self.lastError = lastError
        self.onToggleOverlay = onToggleOverlay
        self.onToggleExpand = onToggleExpand
        self.onRefresh = onRefresh
        self.onSearchLyrics = onSearchLyrics
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onOpenDonate = onOpenDonate
        self.onReportBug = onReportBug
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyrinotch")
                    .font(.headline)

                HStack(alignment: .top, spacing: 6) {
                    Text(playbackGlyph)
                    Text(trackTitle)
                        .lineLimit(2)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)

                Text(lyricsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(islandModeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Quick actions
            VStack(spacing: 2) {
                menuButton(
                    title: isOverlayVisible ? L10n.t("menu.hide_overlay") : L10n.t("menu.show_overlay"),
                    systemImage: isOverlayVisible ? "eye.slash" : "eye"
                ) {
                    onToggleOverlay()
                }
                .keyboardShortcut("h", modifiers: [.command])

                menuButton(
                    title: isIslandExpanded
                        ? L10n.t("menu.collapse_overlay")
                        : L10n.t("menu.expand_overlay"),
                    systemImage: isIslandExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                ) {
                    onToggleExpand()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                menuButton(
                    title: L10n.t("menu.search_lyrics"),
                    systemImage: "magnifyingglass"
                ) {
                    onSearchLyrics()
                }

                menuButton(
                    title: L10n.t("menu.refresh"),
                    systemImage: "arrow.clockwise"
                ) {
                    onRefresh()
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)

            Divider()

            VStack(spacing: 2) {
                menuButton(
                    title: L10n.t("menu.settings"),
                    systemImage: "gearshape"
                ) {
                    onOpenSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])

                menuButton(
                    title: L10n.t("menu.about"),
                    systemImage: "info.circle"
                ) {
                    onOpenAbout()
                }

                menuButton(
                    title: L10n.t("menu.support"),
                    systemImage: "heart.fill"
                ) {
                    onOpenDonate()
                }

                menuButton(
                    title: L10n.t("menu.report_bug"),
                    systemImage: "ladybug"
                ) {
                    onReportBug()
                }

                Divider()
                    .padding(.vertical, 4)

                menuButton(
                    title: L10n.t("menu.quit"),
                    systemImage: "power",
                    role: .destructive
                ) {
                    onQuit()
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: 280)
        .id(L10n.current)
    }

    private func menuButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
