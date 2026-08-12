import SwiftUI
import LyrinotchCore

/// Guided, local-only editor that records one playback-time anchor per lyric line.
@MainActor
struct TapSyncView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("tap_sync.title"))
                .font(.title2.weight(.semibold))

            Text(model.menuTrackTitle)
                .font(.headline)
                .lineLimit(2)

            if let project = model.tapSyncProject {
                editor(project)
            } else {
                ContentUnavailableView(
                    L10n.t("tap_sync.unavailable_title"),
                    systemImage: "waveform.badge.exclamationmark",
                    description: Text(
                        model.tapSyncStatusText ?? L10n.t("tap_sync.needs_plain_lyrics")
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                Button(L10n.t("search.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 620, height: 680)
        .onAppear { model.prepareTapSync() }
        .onDisappear {
            model.endTapSyncSession()
            UtilityWindowActivation.restoreAccessoryModeIfNeeded()
        }
        .confirmationDialog(
            L10n.t("tap_sync.reset_confirm"),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(L10n.t("tap_sync.reset"), role: .destructive) {
                model.resetTapSyncProject()
            }
            Button(L10n.t("search.close"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func editor(_ project: TapSyncProject) -> some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            HStack(spacing: 12) {
                Text(formatTime(model.tapSyncPlaybackPosition))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(model.tapSyncIsPlaying
                    ? L10n.t("tap_sync.playing")
                    : L10n.t("tap_sync.paused"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    L10n.t(
                        "tap_sync.progress",
                        model.tapSyncAnchorCount,
                        model.tapSyncUsableLineCount
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("tap_sync.current_line"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.tapSyncSelectedLineText ?? L10n.t("tap_sync.no_line"))
                .font(.title3.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

        HStack(spacing: 8) {
            Button(L10n.t("tap_sync.seek_start")) {
                model.tapSyncSeekToStart()
            }
            Button(L10n.t("tap_sync.back_five")) {
                model.tapSyncSeekBackward()
            }
            Button(model.tapSyncIsPlaying
                ? L10n.t("tap_sync.pause")
                : L10n.t("tap_sync.play"))
            {
                model.tapSyncTogglePlayback()
            }
            Spacer()
            Button(L10n.t("tap_sync.previous_line")) {
                model.moveTapSyncSelection(by: -1)
            }
            Button(L10n.t("tap_sync.next_line")) {
                model.moveTapSyncSelection(by: 1)
            }
        }
        .buttonStyle(.bordered)

        Button {
            model.recordTapSyncAnchorNow()
        } label: {
            Label(L10n.t("tap_sync.mark_now"), systemImage: "hand.tap.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(" ", modifiers: [])
        .disabled(model.tapSyncSelectedLineText == nil)

        Text(L10n.t("tap_sync.help"))
            .font(.caption)
            .foregroundStyle(.secondary)

        if let status = model.tapSyncStatusText, !status.isEmpty {
            Text(status)
                .font(.caption)
        }

        List {
            ForEach(Array(project.lineTexts.enumerated()), id: \.offset) { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                Button {
                    model.selectTapSyncLine(index)
                } label: {
                    HStack(spacing: 10) {
                        if let time = model.tapSyncAnchorTime(for: index) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(formatTime(time))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .trailing)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                            Text("—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 54, alignment: .trailing)
                        }
                        Text(trimmed.isEmpty ? L10n.t("tap_sync.blank_line") : trimmed)
                            .foregroundStyle(trimmed.isEmpty ? .tertiary : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)
                .listRowBackground(
                    model.tapSyncSelectedLineIndex == index
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
            }
        }
        .frame(minHeight: 220)

        HStack(spacing: 8) {
            Button(L10n.t("tap_sync.undo")) {
                model.undoTapSyncAnchor()
            }
            .disabled(project.canUndo == false)

            Button(L10n.t("tap_sync.reset"), role: .destructive) {
                isConfirmingReset = true
            }
            .disabled(project.anchors.isEmpty)

            Spacer()

            Button(L10n.t("tap_sync.save_timeline")) {
                model.finishTapSync()
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.anchors.isEmpty)
        }
        .buttonStyle(.bordered)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--.-" }
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let remainder = clamped - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainder)
    }
}
