import Foundation
import Observation
import LyrinotchCore

/// Owns manual-search form state, cancellation, and stale-query protection.
@MainActor
@Observable
final class LyricsSearchState {
    var query = ""
    var hits: [LyricsSearchHit] = []
    var isSearching = false
    var error: String?
    private(set) var targetTrackKey: String?
    private(set) var isActive = false
    private var task: Task<Void, Never>?
    private var requestGeneration = 0

    func prepare(for track: Track?, trackKey: String?) {
        stop(resetPresentation: false)
        isActive = true
        targetTrackKey = trackKey
        query = track.map { "\($0.artist) \($0.name)" } ?? ""
        hits = []
        error = track == nil ? L10n.t("search.no_current_track") : nil
    }

    /// Invalidates visible results when the player changes underneath an open
    /// search window. A result is meaningful only for the track that initiated
    /// the search.
    func trackDidChange(to track: Track?, trackKey: String?) {
        guard isActive, targetTrackKey != trackKey else { return }
        stop(resetPresentation: false)
        isActive = true
        targetTrackKey = trackKey
        query = track.map { "\($0.artist) \($0.name)" } ?? ""
        hits = []
        error = track == nil
            ? L10n.t("search.no_current_track")
            : L10n.t("search.track_changed")
    }

    func canApply(to trackKey: String) -> Bool {
        isActive && targetTrackKey == trackKey
    }

    func run(using service: LyricsService) {
        run(search: { query in
            try await service.search(query: query)
        })
    }

    func run(
        search: @escaping (String) async throws -> [LyricsSearchHit]
    ) {
        let submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard submitted.count >= 2 else {
            error = L10n.t("search.query_too_short")
            return
        }
        requestGeneration &+= 1
        let generation = requestGeneration
        isSearching = true
        error = nil
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if requestGeneration == generation {
                    isSearching = false
                    task = nil
                }
            }
            do {
                let results = try await search(submitted)
                guard !Task.isCancelled,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == submitted
                else { return }
                hits = results
                if results.isEmpty { error = L10n.t("search.no_results") }
            } catch {
                guard !Task.isCancelled,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == submitted
                else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func stop() {
        stop(resetPresentation: true)
    }

    private func stop(resetPresentation: Bool) {
        requestGeneration &+= 1
        task?.cancel()
        task = nil
        isSearching = false
        if resetPresentation {
            isActive = false
            targetTrackKey = nil
            hits = []
            error = nil
        }
    }
}
