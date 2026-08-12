import AppKit
import Combine
import SwiftUI
import LyrinotchCore

/// The complete set of values rendered by the overlay at one point in time.
/// Publishing one snapshot keeps a frame update atomic and avoids triggering a
/// separate SwiftUI invalidation for every individual field.
struct NotchOverlayContent {
    var track: Track
    var lines: [LyricLine]
    var position: TimeInterval
    var lyricsAvailability: LyricsAvailability
    var appearance: OverlayAppearance
    var statusMessage: String?
    var islandMode: IslandMode
    var deviceNotchSize: CGSize
    var hasPhysicalNotch: Bool
    var presentationStyle: OverlayPresentationStyle
    var expandLocked: Bool
    var playerSource: MusicPlayerSource?
    var artwork: NSImage?
    var lyricAccent: Color?
    var islandExtraWidth: CGFloat
    var translationText: String?
    var isLoadingLyrics: Bool
    var syncStatusText: String?
    var trackOffsetSeconds: Double
    var hasTrackOffset: Bool
}

struct NotchOverlayCallbacks {
    var onToggleExpand: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onRefreshLyrics: (() -> Void)?
    var onNudgeTrackOffset: ((Double) -> Void)?
    var onResetTrackOffset: (() -> Void)?
}

@MainActor
final class NotchOverlayViewState: ObservableObject {
    @Published private(set) var content: NotchOverlayContent

    init(content: NotchOverlayContent) {
        self.content = content
    }

    func update(_ content: NotchOverlayContent) {
        self.content = content
    }
}

/// Stable root installed in `NSHostingView` exactly once. Subsequent playback
/// ticks only publish a new content snapshot, allowing SwiftUI to diff the view
/// tree while preserving local state such as the scrubber interaction.
@MainActor
struct StatefulNotchOverlayView: View {
    @ObservedObject var state: NotchOverlayViewState
    let callbacks: NotchOverlayCallbacks

    var body: some View {
        let content = state.content
        NotchOverlayView(
            track: content.track,
            lines: content.lines,
            position: content.position,
            lyricsAvailability: content.lyricsAvailability,
            appearance: content.appearance,
            statusMessage: content.statusMessage,
            islandMode: content.islandMode,
            deviceNotchSize: content.deviceNotchSize,
            hasPhysicalNotch: content.hasPhysicalNotch,
            presentationStyle: content.presentationStyle,
            expandLocked: content.expandLocked,
            playerSource: content.playerSource,
            artwork: content.artwork,
            lyricAccent: content.lyricAccent,
            islandExtraWidth: content.islandExtraWidth,
            translationText: content.translationText,
            isLoadingLyrics: content.isLoadingLyrics,
            syncStatusText: content.syncStatusText,
            trackOffsetSeconds: content.trackOffsetSeconds,
            hasTrackOffset: content.hasTrackOffset,
            onToggleExpand: callbacks.onToggleExpand,
            onPlayPause: callbacks.onPlayPause,
            onNext: callbacks.onNext,
            onPrevious: callbacks.onPrevious,
            onSeek: callbacks.onSeek,
            onRefreshLyrics: callbacks.onRefreshLyrics,
            onNudgeTrackOffset: callbacks.onNudgeTrackOffset,
            onResetTrackOffset: callbacks.onResetTrackOffset
        )
    }
}

/// Owns the stable AppKit/SwiftUI bridge. Keeping this tiny object separate also
/// makes the one-time root installation invariant directly testable.
@MainActor
final class NotchOverlayRenderer {
    let state: NotchOverlayViewState
    let hostingView: PassThroughHostingView<StatefulNotchOverlayView>

    init(content: NotchOverlayContent, callbacks: NotchOverlayCallbacks) {
        let state = NotchOverlayViewState(content: content)
        self.state = state
        self.hostingView = PassThroughHostingView(
            rootView: StatefulNotchOverlayView(state: state, callbacks: callbacks)
        )
    }

    func update(_ content: NotchOverlayContent) {
        state.update(content)
    }
}
