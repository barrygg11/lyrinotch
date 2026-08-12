import SwiftUI
import LyrinotchCore

/// Stable tab identifiers keep the selected tab in place when the UI language changes.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case overlay
    case lyrics
    case appearance
    case players

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .general: return "tab.general"
        case .overlay: return "tab.display"
        case .lyrics: return "tab.lyrics"
        case .appearance: return "tab.appearance"
        case .players: return "tab.system"
        }
    }
}

/// Full settings window — long-lived preferences only.
@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        // Explicit segmented navigation avoids AppKit collapsing localized tab items
        // into the overflow "more toolbar items" menu.
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(L10n.t(tab.titleKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(model: model)
                case .overlay:
                    OverlaySettingsTab(model: model)
                case .lyrics:
                    LyricsSettingsTab(model: model)
                case .appearance:
                    AppearanceSettingsTab(model: model)
                case .players:
                    PlayerSettingsTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(
            minWidth: settingsWindowWidth,
            idealWidth: settingsWindowWidth,
            maxWidth: settingsWindowWidth + 40
        )
        .frame(minHeight: 500, idealHeight: 520)
        // L10n is intentionally lightweight rather than Observable. Rebuild labels while
        // the selection binding above preserves the user's current location.
        .id("\(model.preferredLanguage.rawValue)-\(model.preferredLanguage.resolved.rawValue)")
        .environment(\.locale, model.preferredLanguage.resolved.locale)
    }

    private var settingsWindowWidth: CGFloat {
        switch model.preferredLanguage.resolved {
        case .english, .japanese:
            return 560
        case .traditionalChinese, .simplifiedChinese, .system:
            return 500
        }
    }
}
