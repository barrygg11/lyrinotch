import SwiftUI
import LyrinotchCore

@MainActor
struct GeneralSettingsTab: View {
    @Bindable var model: AppModel
    @State private var confirmsDataClear = false

    var body: some View {
        Form {
            Section(L10n.t("section.language")) {
                Picker(L10n.t("picker.language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeDisplayName).tag(language)
                    }
                }
                SettingsHelpText(L10n.t("help.language"))
            }

            Section(L10n.t("section.login")) {
                Toggle(L10n.t("toggle.launch_at_login"), isOn: launchAtLoginBinding)
            }

            Section(L10n.t("section.hotkeys")) {
                Toggle(L10n.t("toggle.hotkeys"), isOn: hotKeyBinding)
                SettingsHelpText(L10n.t("help.hotkeys"))

                if hotKeyRegistrationFailed {
                    SettingsHelpText(model.hotKeyStatusText, tone: .error)
                }
            }

            Section(L10n.t("section.local_data")) {
                Button(L10n.t("button.clear_local_lyrics"), role: .destructive) {
                    confirmsDataClear = true
                }
                SettingsHelpText(L10n.t("help.clear_local_lyrics"), tone: .tertiary)
            }

            UpdateSettingsSection()
        }
        .formStyle(.grouped)
        .padding()
        .alert(L10n.t("data.clear_title"), isPresented: $confirmsDataClear) {
            Button(L10n.t("button.cancel"), role: .cancel) {}
            Button(L10n.t("button.clear"), role: .destructive) {
                model.clearStoredLyricsAndOffsets()
            }
        } message: {
            Text(L10n.t("data.clear_message"))
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { model.preferredLanguage },
            set: { model.setPreferredLanguage($0) }
        )
    }

    private var hotKeyBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.hotKeyEnabled },
            set: { model.setHotKeyEnabled($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    private var hotKeyRegistrationFailed: Bool {
        model.preferences.hotKeyEnabled
            && model.hotKeyStatusText == L10n.t("hotkey.fail")
    }

}
