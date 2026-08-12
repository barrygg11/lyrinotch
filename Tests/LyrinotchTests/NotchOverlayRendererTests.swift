import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class NotchOverlayRendererTests: XCTestCase {
    @MainActor
    func testContentUpdatesPreserveHostingViewAndRootStateIdentity() {
        let renderer = NotchOverlayRenderer(
            content: makeContent(position: 0, style: .notchIsland),
            callbacks: NotchOverlayCallbacks()
        )
        let hostingView = renderer.hostingView
        let rootState = hostingView.rootView.state

        renderer.update(makeContent(position: 42, style: .floatingHUD))

        XCTAssertTrue(hostingView === renderer.hostingView)
        XCTAssertTrue(rootState === renderer.state)
        XCTAssertTrue(hostingView.rootView.state === rootState)
        XCTAssertEqual(renderer.state.content.position, 42)
        XCTAssertEqual(renderer.state.content.presentationStyle, .floatingHUD)
    }

    @MainActor
    func testStableRootCallbacksObserveLatestControllerCallbackTarget() {
        var playPauseCount = 0
        var callback: (() -> Void)? = { playPauseCount += 1 }
        let renderer = NotchOverlayRenderer(
            content: makeContent(position: 0, style: .notchIsland),
            callbacks: NotchOverlayCallbacks(onPlayPause: { callback?() })
        )
        let originalRoot = renderer.hostingView.rootView

        renderer.update(makeContent(position: 1, style: .floatingHUD))
        callback = { playPauseCount += 10 }
        originalRoot.callbacks.onPlayPause?()

        XCTAssertEqual(playPauseCount, 10)
        XCTAssertTrue(renderer.hostingView.rootView.state === originalRoot.state)
    }

    @MainActor
    private func makeContent(
        position: TimeInterval,
        style: OverlayPresentationStyle
    ) -> NotchOverlayContent {
        NotchOverlayContent(
            track: .empty,
            lines: [],
            position: position,
            lyricsAvailability: .skipped,
            appearance: .default,
            statusMessage: nil,
            islandMode: .collapsed,
            deviceNotchSize: CGSize(width: 180, height: 32),
            hasPhysicalNotch: style == .notchIsland,
            presentationStyle: style,
            expandLocked: false,
            playerSource: nil,
            artwork: nil,
            lyricAccent: nil,
            islandExtraWidth: 0,
            translationText: nil,
            isLoadingLyrics: false,
            syncStatusText: nil,
            trackOffsetSeconds: 0,
            hasTrackOffset: false
        )
    }
}
