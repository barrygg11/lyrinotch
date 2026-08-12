import SwiftUI
import LyrinotchCore

@MainActor
struct PlayerSettingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section(L10n.t("player.preference.section")) {
                Picker(
                    L10n.t("player.preference.label"),
                    selection: Binding(
                        get: { model.preferences.playerSelectionPreference },
                        set: { model.setPlayerSelectionPreference($0) }
                    )
                ) {
                    ForEach(PlayerSelectionPreference.allCases) { preference in
                        Text(L10n.t(preference.displayNameKey)).tag(preference)
                    }
                }
                SettingsHelpText(L10n.t("player.preference.help"))
            }

            AutomationPermissionsSection(errorMessage: playerErrorMessage)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var playerErrorMessage: String? {
        if let warning = model.playbackWarning { return warning }
        guard model.nowPlaying.availability == .error else { return nil }
        return model.nowPlaying.detail ?? model.lastError
    }
}
