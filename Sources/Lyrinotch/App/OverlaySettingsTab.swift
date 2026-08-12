import AppKit
import SwiftUI
import LyrinotchCore

/// Picker selection identity for connected displays — keyed by display ID only so
/// legacy or mismatched stored display names never desync the live control.
enum ScreenPickerSelection: Hashable {
    case mouseCursor
    case specific(displayID: UInt32)
    case mainDisplay
    case preferNotched

    init(_ placement: ScreenPlacement) {
        switch placement {
        case .mouseCursor:
            self = .mouseCursor
        case .specific(let id, _):
            self = .specific(displayID: id)
        case .mainDisplay:
            self = .mainDisplay
        case .preferNotched:
            self = .preferNotched
        }
    }
}

@MainActor
struct OverlaySettingsTab: View {
    @Bindable var model: AppModel
    @State private var connectedScreens: [NSScreen] = NSScreen.screens
    @State private var macModelName: String?
    @State private var isAdvancedLayoutExpanded = false

    var body: some View {
        Form {
            Section(L10n.t("section.screen")) {
                Toggle(L10n.t("toggle.show_overlay"), isOn: overlayVisibleBinding)

                Picker(L10n.t("picker.screen"), selection: screenPlacementBinding) {
                    Text(L10n.t("screen.mouse")).tag(ScreenPickerSelection.mouseCursor)

                    ForEach(connectedScreens, id: \.lyrinotchDisplayID) { screen in
                        Text(screen.lyrinotchPickerLabel(modelName: macModelName))
                            .tag(ScreenPickerSelection.specific(displayID: screen.lyrinotchDisplayID))
                    }

                    if case .mainDisplay = model.preferences.screenPlacement {
                        Text(L10n.t("screen.main")).tag(ScreenPickerSelection.mainDisplay)
                    }
                    if case .preferNotched = model.preferences.screenPlacement {
                        Text(L10n.t("screen.notched")).tag(ScreenPickerSelection.preferNotched)
                    }
                    if case .specific(let id, let name) = model.preferences.screenPlacement,
                       !connectedScreens.contains(where: { $0.lyrinotchDisplayID == id })
                    {
                        let label = name.isEmpty
                            ? L10n.t("screen.missing", "\(id)")
                            : L10n.t("screen.missing_named", name)
                        Text(label)
                            .tag(ScreenPickerSelection.specific(displayID: id))
                    }
                }
                SettingsHelpText(L10n.t("help.screen_picker"))

                Toggle(L10n.t("toggle.hide_fullscreen"), isOn: hideInFullscreenBinding)
            }

            Section(L10n.t("section.behavior")) {
                Picker(L10n.t("picker.resting_mode"), selection: preferExpandedBinding) {
                    Text(L10n.t("mode.auto_collapse")).tag(false)
                    Text(L10n.t("mode.keep_expanded")).tag(true)
                }
                .pickerStyle(.segmented)

                SettingsHelpText(L10n.t("help.resting_mode"))

                if !model.preferences.preferExpanded {
                    Toggle(
                        L10n.t("toggle.expand_on_track_change"),
                        isOn: expandOnTrackChangeBinding
                    )
                }
            }

            Section(L10n.t("section.expanded_content")) {
                Toggle(L10n.t("toggle.show_track_title"), isOn: showTrackTitleBinding)
                Toggle(L10n.t("toggle.show_adjacent"), isOn: showAdjacentBinding)
            }

            Section(L10n.t("section.interaction")) {
                Toggle(L10n.t("toggle.click_through"), isOn: clickThroughBinding)
                SettingsHelpText(L10n.t("help.click_through"))
            }

            Section {
                DisclosureGroup(
                    isExpanded: $isAdvancedLayoutExpanded,
                    content: {
                        SettingsSliderRow(
                            L10n.t("layout.vertical_offset", Int(model.preferences.verticalOffset)),
                            value: verticalOffsetBinding,
                            in: -8...32,
                            step: 1
                        )

                        SettingsSliderRow(
                            L10n.t("layout.island_width", Int(model.preferences.islandExtraWidth)),
                            value: islandExtraWidthBinding,
                            in: 0...120,
                            step: 4
                        )

                        Button(L10n.t("button.reset_layout")) {
                            model.resetOverlayLayout()
                        }
                        .disabled(isDefaultLayout)
                    },
                    label: {
                        Label(L10n.t("section.layout"), systemImage: "ruler")
                    }
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            macModelName = await MacHardwareInfoProvider.shared.modelName()
        }
        .onAppear { refreshConnectedScreens() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            refreshConnectedScreens()
        }
    }

    private var isDefaultLayout: Bool {
        abs(model.preferences.verticalOffset) < 0.01
            && abs(model.preferences.islandExtraWidth) < 0.01
    }

    private var overlayVisibleBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.isOverlayVisible },
            set: { model.setOverlayVisible($0) }
        )
    }

    private var screenPlacementBinding: Binding<ScreenPickerSelection> {
        Binding(
            get: { ScreenPickerSelection(model.preferences.screenPlacement) },
            set: { selection in
                switch selection {
                case .mouseCursor:
                    model.setScreenPlacement(.mouseCursor)
                case .mainDisplay:
                    model.setScreenPlacement(.mainDisplay)
                case .preferNotched:
                    model.setScreenPlacement(.preferNotched)
                case .specific(let id):
                    if let screen = connectedScreens.first(where: { $0.lyrinotchDisplayID == id }) {
                        model.setScreenPlacement(
                            .specific(displayID: id, displayName: screen.localizedName)
                        )
                    } else if case .specific(let savedID, let savedName) = model.preferences.screenPlacement,
                              savedID == id
                    {
                        // Missing saved screen: keep existing stored name.
                        model.setScreenPlacement(
                            .specific(displayID: id, displayName: savedName)
                        )
                    } else {
                        model.setScreenPlacement(
                            .specific(displayID: id, displayName: "")
                        )
                    }
                }
            }
        )
    }

    private var hideInFullscreenBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.hideInFullscreen },
            set: { model.setHideInFullscreen($0) }
        )
    }

    private var preferExpandedBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.preferExpanded },
            set: { model.setPreferExpanded($0) }
        )
    }

    private var expandOnTrackChangeBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.expandOnTrackChange },
            set: { model.setExpandOnTrackChange($0) }
        )
    }

    private var showTrackTitleBinding: Binding<Bool> {
        Binding(
            get: { model.appearance.showTrackTitle },
            set: { model.setShowTrackTitle($0) }
        )
    }

    private var showAdjacentBinding: Binding<Bool> {
        Binding(
            get: { model.appearance.showAdjacentLines },
            set: { model.setShowAdjacentLines($0) }
        )
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(
            get: { model.appearance.clickThrough },
            set: { model.setClickThrough($0) }
        )
    }

    private var verticalOffsetBinding: Binding<Double> {
        Binding(
            get: { model.preferences.verticalOffset },
            set: { model.setVerticalOffset($0) }
        )
    }

    private var islandExtraWidthBinding: Binding<Double> {
        Binding(
            get: { model.preferences.islandExtraWidth },
            set: { model.setIslandExtraWidth($0) }
        )
    }

    private func refreshConnectedScreens() {
        connectedScreens = NSScreen.screens
    }
}
