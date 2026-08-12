import Foundation
import SwiftUI
import UniformTypeIdentifiers
import LyrinotchCore

@MainActor
struct LyricsSettingsTab: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isTrackCalibrationExpanded = false
    @State private var isSelectingLocalLRC = false

    var body: some View {
        Form {
            Section(L10n.t("section.lyrics_source")) {
                Picker(L10n.t("picker.lyrics_source"), selection: lyricsSourceBinding) {
                    ForEach(LyricsSourcePreference.settingsCases, id: \.self) { preference in
                        Text(L10n.t(preference.displayNameKey)).tag(preference)
                    }
                }
                SettingsHelpText(L10n.t("help.lyrics_source"))
            }

            Section(L10n.t("section.lyrics_content")) {
                Toggle(
                    L10n.t("toggle.display_traditional"),
                    isOn: displayTraditionalBinding
                )

                Toggle(
                    L10n.t("toggle.show_translation"),
                    isOn: showTranslationBinding
                )
                SettingsHelpText(L10n.t("help.show_translation"))

                if model.preferences.showTranslation {
                    Picker(
                        L10n.t("picker.translation_target"),
                        selection: translationTargetBinding
                    ) {
                        Text("繁體中文").tag("zh-TW")
                        Text("简体中文").tag("zh-CN")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                    }
                }
            }

            Section(L10n.t("section.lyrics_timing")) {
                Toggle(
                    L10n.t("toggle.auto_calibrate_offset"),
                    isOn: autoCalibrateOffsetBinding
                )
                SettingsHelpText(L10n.t("help.auto_calibrate_offset"))

                SettingsSliderRow(
                    L10n.t("layout.lyric_offset", formattedOffset(model.globalLyricOffsetSeconds)),
                    value: lyricOffsetBinding,
                    in: -5...5,
                    step: 0.1
                )

                HStack(spacing: 8) {
                    Button(L10n.t("button.offset_minus")) {
                        model.nudgeLyricOffset(by: -0.5)
                    }
                    Button(L10n.t("button.offset_plus")) {
                        model.nudgeLyricOffset(by: 0.5)
                    }
                    Button(L10n.t("button.offset_reset")) {
                        model.resetLyricOffset()
                    }
                    .disabled(abs(model.globalLyricOffsetSeconds) < 0.05)
                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)

                SettingsHelpText(L10n.t("help.lyric_offset"), tone: .tertiary)
            }

            Section(L10n.t("section.lyrics_timeline_tools")) {
                Text(model.menuLyricsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if model.shouldOfferSyncedLyricsSearch {
                        Button {
                            openWindow(id: "lyrics-search")
                        } label: {
                            Label(
                                L10n.t("button.search_synced_lyrics"),
                                systemImage: "magnifyingglass"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        isSelectingLocalLRC = true
                    } label: {
                        Label(
                            L10n.t("button.import_lrc"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasCurrentTrack || model.isImportingLocalLRC)

                    Button {
                        openWindow(id: "tap-sync")
                    } label: {
                        Label(
                            L10n.t("button.tap_sync"),
                            systemImage: "hand.tap"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canStartTapSync)

                    Spacer(minLength: 0)
                }

                if model.isImportingLocalLRC {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.t("lrc_import.reading"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let status = model.lyricsTimelineOperationStatusText,
                          !status.isEmpty
                {
                    Text(status)
                        .font(.caption)
                }

                if model.shouldOfferSyncedLyricsSearch {
                    SettingsHelpText(
                        L10n.t("help.search_synced_lyrics"),
                        tone: .tertiary
                    )
                }
                SettingsHelpText(L10n.t("help.import_lrc"), tone: .tertiary)
                SettingsHelpText(L10n.t("help.tap_sync_entry"), tone: .tertiary)
            }

            Section {
                DisclosureGroup(
                    isExpanded: $isTrackCalibrationExpanded,
                    content: {
                        Label(model.menuTrackTitle, systemImage: "music.note")
                            .lineLimit(2)

                        Text(offsetBreakdownText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let status = model.offsetCalibrationStatusText, !status.isEmpty {
                            Text(status)
                                .font(.caption)
                        }

                        HStack(spacing: 8) {
                            Button(L10n.t("button.track_offset_slow")) {
                                model.nudgeTrackAutoOffset(by: 0.5)
                            }
                            Button(L10n.t("button.track_offset_fast")) {
                                model.nudgeTrackAutoOffset(by: -0.5)
                            }
                            Button(L10n.t("button.align_next_line")) {
                                model.alignOffsetToNextLineNow()
                            }
                            Spacer(minLength: 0)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasCurrentTrack)

                        SettingsHelpText(
                            L10n.t("help.manual_track_offset"),
                            tone: .tertiary
                        )

                        HStack(spacing: 8) {
                            Button(L10n.t("button.recalibrate_offset")) {
                                model.recalibrateCurrentTrackOffset()
                            }
                            Button(L10n.t("button.clear_track_offset")) {
                                model.clearCurrentTrackAutoOffset()
                            }
                            Spacer(minLength: 0)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasCurrentTrack)
                    },
                    label: {
                        Label(L10n.t("section.track_calibration"), systemImage: "metronome")
                    }
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $isSelectingLocalLRC,
            allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText]
        ) { result in
            switch result {
            case .success(let url):
                model.importLocalLRC(from: url)
            case .failure(let error):
                model.reportLocalLRCSelectionError(error)
            }
        }
    }

    private var hasCurrentTrack: Bool {
        model.nowPlaying.availability == .ready
    }

    private var offsetBreakdownText: String {
        L10n.t(
            "offset_cal.breakdown",
            formattedNumber(model.effectiveLyricOffsetSeconds),
            formattedNumber(model.globalLyricOffsetSeconds),
            formattedNumber(model.trackLyricOffsetSeconds)
        )
    }

    private func formattedOffset(_ value: Double) -> String {
        abs(value) < 0.05 ? "0.0 s" : "\(formattedNumber(value)) s"
    }

    private func formattedNumber(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private var lyricsSourceBinding: Binding<LyricsSourcePreference> {
        Binding(
            get: { model.preferences.lyricsSourcePreference },
            set: { model.setLyricsSourcePreference($0) }
        )
    }

    private var displayTraditionalBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.displayTraditionalChinese },
            set: { model.setDisplayTraditionalChinese($0) }
        )
    }

    private var showTranslationBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.showTranslation },
            set: { model.setShowTranslation($0) }
        )
    }

    private var translationTargetBinding: Binding<String> {
        Binding(
            get: { model.preferences.translationTargetLanguage },
            set: { model.setTranslationTargetLanguage($0) }
        )
    }

    private var autoCalibrateOffsetBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.autoCalibrateLyricOffset },
            set: { model.setAutoCalibrateLyricOffset($0) }
        )
    }

    private var lyricOffsetBinding: Binding<Double> {
        Binding(
            get: { model.preferences.lyricOffsetSeconds },
            set: { model.setLyricOffsetSeconds($0) }
        )
    }
}
