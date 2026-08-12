import SwiftUI
import LyrinotchCore

/// Owns update-check/install UI state so the main Settings view stays declarative.
@MainActor
struct UpdateSettingsSection: View {
    @State private var statusMessage: String?
    @State private var releaseURL: URL?
    @State private var asset: UpdateChecker.UpdateAsset?
    @State private var availableVersion: String?
    @State private var showConfirmation = false
    @State private var isChecking = false
    @State private var isInstalling = false
    @State private var installProgress = 0.0

    var body: some View {
        Section(L10n.t("section.updates")) {
            LabeledContent(L10n.t("settings.current_version")) {
                Text(AppInfo.versionWithBuild)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                Task { await checkForUpdates() }
            } label: {
                if isChecking {
                    Label(L10n.t("update.checking"), systemImage: "arrow.triangle.2.circlepath")
                } else if isInstalling {
                    Label(L10n.t("update.installing"), systemImage: "arrow.down.circle.fill")
                } else {
                    Label(L10n.t("update.check"), systemImage: "arrow.down.circle")
                }
            }
            .disabled(isChecking || isInstalling)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if isInstalling {
                ProgressView(value: installProgress, total: 1)
                    .progressViewStyle(.linear)
            }

            if asset != nil, UpdateChecker.canInstallAutomatically {
                Button {
                    showConfirmation = true
                } label: {
                    Label(L10n.t("update.install"), systemImage: "arrow.down.app.fill")
                }
                .disabled(isInstalling || isChecking)
            }

            if let releaseURL {
                Button {
                    _ = UpdateChecker.openReleasePage(releaseURL)
                } label: {
                    Label(L10n.t("update.open_release"), systemImage: "safari")
                }
                .disabled(isInstalling)
            }
        }
        .alert(L10n.t("update.confirm_title"), isPresented: $showConfirmation) {
            Button(L10n.t("update.install")) {
                guard let asset, let availableVersion else { return }
                Task { await install(asset: asset, expectedVersion: availableVersion) }
            }
            Button(L10n.t("update.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("update.confirm_message", availableVersion ?? ""))
        }
    }

    private func checkForUpdates() async {
        isChecking = true
        releaseURL = nil
        asset = nil
        availableVersion = nil
        installProgress = 0
        statusMessage = L10n.t("update.checking")
        let outcome = await UpdateChecker.checkForUpdates()
        isChecking = false

        switch outcome {
        case .notConfigured:
            statusMessage = L10n.t("update.not_configured")
        case .upToDate(let current, let latest):
            statusMessage = L10n.t("update.up_to_date", current, latest)
        case .updateAvailable(let current, let latest, let url, let updateAsset):
            releaseURL = url
            asset = updateAsset
            availableVersion = latest
            if updateAsset != nil, UpdateChecker.canInstallAutomatically {
                statusMessage = L10n.t("update.available", latest, current)
            } else if updateAsset != nil {
                statusMessage = L10n.t("update.available_manual_only", latest, current)
            } else {
                statusMessage = L10n.t("update.available_no_dmg", latest, current)
            }
        case .failed(let message):
            statusMessage = message
        }
    }

    private func install(asset: UpdateChecker.UpdateAsset, expectedVersion: String) async {
        isInstalling = true
        installProgress = 0
        statusMessage = L10n.t("update.installing")
        let outcome = await UpdateChecker.installUpdate(
            asset: asset,
            expectedVersion: expectedVersion
        ) { progress in
            Task { @MainActor in installProgress = progress }
        }
        switch outcome {
        case .success:
            installProgress = 1
            statusMessage = L10n.t("update.install_done")
        case .failed(let message):
            statusMessage = message
            isInstalling = false
        }
    }
}
