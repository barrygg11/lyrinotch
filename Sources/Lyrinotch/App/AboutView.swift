import AppKit
import SwiftUI
import LyrinotchCore

/// Standalone About window: brand, version, maintainer + support channel strip.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var didCopyDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                aboutIcon
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)

                Text("Lyrinotch")
                    .font(.title2.weight(.semibold))

                VStack(spacing: 4) {
                    Text(AppInfo.versionWithBuild)
                        .font(.subheadline.monospacedDigit())
                    Text("\(L10n.t("about.maintainer")) \(AppInfo.maintainer)")
                    Text(AppInfo.minimumSystemLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Text(L10n.t("about.tagline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Text(L10n.t("support.blurb"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if AppInfo.hasAnySupportLink {
                    SupportChannelsStrip(style: .compact)
                } else {
                    Text(L10n.t("about.support_hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    _ = AppInfo.copyDiagnosticsToPasteboard()
                    didCopyDiagnostics = true
                } label: {
                    Label(
                        didCopyDiagnostics
                            ? L10n.t("about.copy_diagnostics_done")
                            : L10n.t("about.copy_diagnostics"),
                        systemImage: "doc.on.clipboard"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text(AppInfo.copyrightLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button(L10n.t("about.open_disclaimer")) {
                    openWindow(id: "disclaimer")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button(L10n.t("about.close")) {
                    dismissAboutWindow()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 340, height: AppInfo.hasAnySupportLink ? 480 : 460)
        .background(.background)
        .id(L10n.current)
    }

    @ViewBuilder
    @MainActor
    private var aboutIcon: some View {
        if let nsImage = AppInfo.appIconImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black)
                Image(nsImage: MenuBarIcon.nsImage())
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
                    .padding(18)
            }
        }
    }

    @MainActor
    private func dismissAboutWindow() {
        dismiss()
        let title = L10n.t("about.window_title")
        for window in NSApp.windows where window.title == title || window.title == "關於 Lyrinotch" {
            window.close()
        }
    }
}
