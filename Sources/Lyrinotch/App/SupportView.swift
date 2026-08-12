import AppKit
import SwiftUI
import LyrinotchCore

/// Stats-style “Support the application” window.
struct SupportView: View {
    @State private var bugReportHint: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.pink)
                    .symbolRenderingMode(.hierarchical)

                Text(L10n.t("support.window_title"))
                    .font(.title3.weight(.semibold))

                Text(L10n.t("support.blurb"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            SupportChannelsStrip(style: .cards)
                .padding(.horizontal, 20)

            if !AppInfo.hasAnySupportLink {
                Text(L10n.t("support.links_not_set_banner"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Button {
                    let outcome = AppInfo.openBugReport()
                    switch outcome {
                    case .openedWeb: bugReportHint = L10n.t("bug.opened_web")
                    case .openedMail: bugReportHint = L10n.t("bug.opened_mail")
                    case .copiedOnly: bugReportHint = L10n.t("bug.copied_only")
                    }
                } label: {
                    Label(L10n.t("support.report_bug"), systemImage: "ladybug.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if let bugReportHint {
                    Text(bugReportHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(L10n.t("about.close")) {
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 420, height: 340)
        .background(.background)
        .id(L10n.current)
    }

    @MainActor
    private func closeWindow() {
        let title = L10n.t("support.window_title")
        for window in NSApp.windows where window.title == title || window.title == "支持 Lyrinotch" {
            window.close()
        }
    }
}

// MARK: - Channel strip

struct SupportChannelsStrip: View {
    enum Style {
        case cards
        case compact
    }

    var style: Style = .cards

    var body: some View {
        let channels = AppInfo.enabledSupportChannels
        if channels.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: style == .cards ? 14 : 10) {
                ForEach(channels) { channel in
                    channelButton(channel)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func channelButton(_ channel: SupportChannel) -> some View {
        Button {
            AppInfo.open(channel)
        } label: {
            switch style {
            case .cards:
                VStack(spacing: 8) {
                    Image(systemName: channel.systemImage)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(channel.title)
                        .font(.caption.weight(.medium))
                }
                .frame(minWidth: 64)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            case .compact:
                Label(channel.title, systemImage: channel.systemImage)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(style == .cards ? .large : .regular)
        .help(channel.help)
        .accessibilityLabel(channel.help)
    }
}
