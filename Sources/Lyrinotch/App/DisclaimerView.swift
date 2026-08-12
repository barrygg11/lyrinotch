import AppKit
import SwiftUI
import LyrinotchCore

/// Full-screen-friendly legal disclaimer (also summarized under Settings → About).
struct DisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("legal.disclaimer_title"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 12)

            ScrollView {
                Text(L10n.t("legal.disclaimer_body"))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.bottom, 20)

                Text(L10n.t("legal.license_title"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                Text(L10n.t("legal.mit_note"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                Text(L10n.t("legal.mit_body"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.bottom, 16)

                Text(AppInfo.copyrightLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(L10n.t("about.close")) {
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .background(.background)
        .id(L10n.current)
    }

    @MainActor
    private func closeWindow() {
        let title = L10n.t("legal.disclaimer_title")
        for window in NSApp.windows where window.title == title || window.title.contains("免責") || window.title.contains("Disclaimer") {
            window.close()
        }
    }
}
