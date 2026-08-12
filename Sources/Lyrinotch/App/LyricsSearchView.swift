import SwiftUI
import LyrinotchCore

/// Manual provider-aware search — pick a better lyrics match for the current track.
struct LyricsSearchView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var search = model.lyricsSearch
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("search.title"))
                .font(.title2.weight(.semibold))

            Text(L10n.t("search.help"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField(L10n.t("search.placeholder"), text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.runLyricsSearch() }
                Button(L10n.t("search.button")) {
                    model.runLyricsSearch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(search.isSearching || search.targetTrackKey == nil)
            }

            if search.isSearching {
                HStack {
                    ProgressView()
                    Text(L10n.t("status.loading_lyrics"))
                        .foregroundStyle(.secondary)
                }
            }

            if let err = search.error, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            List(search.hits) { hit in
                Button {
                    if model.applyLyricsSearchHit(hit) {
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.trackName)
                            .font(.body.weight(.medium))
                        Text(hit.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 280)

            HStack {
                Button(L10n.t("search.use_automatic")) {
                    model.useAutomaticLyrics()
                    dismiss()
                }
                .disabled(search.targetTrackKey == nil)
                Spacer()
                Button(L10n.t("search.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 480, height: 520)
        .onAppear { model.prepareLyricsSearch() }
        .onDisappear {
            model.stopLyricsSearch()
            UtilityWindowActivation.restoreAccessoryModeIfNeeded()
        }
    }
}
