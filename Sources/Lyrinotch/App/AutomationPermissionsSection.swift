import SwiftUI
import LyrinotchCore

/// Permission-specific state and probes, isolated from the rest of Settings.
@MainActor
struct AutomationPermissionsSection: View {
    let errorMessage: String?
    @State private var permissions = AutomationPermissionsState()

    init(errorMessage: String? = nil) {
        self.errorMessage = errorMessage
    }

    var body: some View {
        Section(L10n.t("section.permissions")) {
            Text(L10n.t("help.permissions"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(target: .appleMusic)
            permissionRow(target: .spotify)
        }

        Section(L10n.t("section.maintenance")) {
            HStack {
                Button {
                    Task { await permissions.verifyAll() }
                } label: {
                    Label(L10n.t("button.check_all_permissions"), systemImage: "checkmark.shield")
                }
                .font(.caption)
                .disabled(permissions.isCheckingAny)

                Spacer()

                Button(action: AutomationPermissionHelper.openSystemAutomationSettings) {
                    Label(L10n.t("button.open_automation_settings"), systemImage: "gearshape")
                }
                .font(.caption)
            }
            .padding(.top, 2)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .task {
            await permissions.refreshPassive()
        }
    }

    private func permissionRow(target: TargetPlayerApp) -> some View {
        HStack {
            Text(target.displayName)
            Spacer()

            if permissions.isChecking(target) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.t("permission.checking"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                permissionStatusRow(target: target)
            }
        }
        .disabled(permissions.isCheckingAny && !permissions.isChecking(target))
    }

    @ViewBuilder
    private func permissionStatusRow(target: TargetPlayerApp) -> some View {
        switch permissions.status(for: target) {
            case .authorized:
                statusLabel("permission.authorized", icon: "checkmark.circle.fill", color: .green)
            case .denied:
                statusActionRow(
                    key: "permission.denied",
                    icon: "xmark.circle.fill",
                    color: .red,
                    buttonKey: "button.open_automation_settings",
                    action: AutomationPermissionHelper.openSystemAutomationSettings
                )
            case .notDetermined:
                statusActionRow(
                    key: "permission.not_determined",
                    icon: "questionmark.circle.fill",
                    color: .orange,
                    buttonKey: "button.request_permission",
                    prominent: true
                ) { request(target) }
            case .unknown:
                statusActionRow(
                    key: "permission.unknown",
                    icon: "ellipsis.circle",
                    color: .secondary,
                    buttonKey: "button.check_permission"
                ) { request(target) }
            case .playerNotRunning:
                statusActionRow(
                    key: "permission.player_not_running",
                    icon: "pause.circle",
                    color: .secondary,
                    buttonKey: "button.check_permission"
                ) { request(target) }
            case .timedOut:
                statusActionRow(
                    key: "permission.timed_out",
                    icon: "clock.badge.exclamationmark",
                    color: .orange,
                    buttonKey: "button.check_permission"
                ) { request(target) }
        }
    }

    private func statusLabel(_ key: String, icon: String, color: Color) -> some View {
        Label(L10n.t(key), systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func statusActionRow(
        key: String,
        icon: String,
        color: Color,
        buttonKey: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            statusLabel(key, icon: icon, color: color)
            if prominent {
                Button(L10n.t(buttonKey), action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(L10n.t(buttonKey), action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func request(_ target: TargetPlayerApp) {
        Task { await permissions.verify(target) }
    }
}
