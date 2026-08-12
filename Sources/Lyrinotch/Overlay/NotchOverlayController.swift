import AppKit
import SwiftUI
import LyrinotchCore

/// Top overlay panel:
/// - **notchIsland**: welded to camera housing (vibe-notch style)
/// - **floatingHUD**: free-floating card below the menu bar on non-notch displays
@MainActor
final class NotchOverlayController {
    private var panel: NotchPanel?
    private var renderer: NotchOverlayRenderer?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    private var moveMonitor: MouseEventMonitor?
    private var clickMonitor: MouseEventMonitor?
    private var hoverOpenWork: DispatchWorkItem?
    /// Display that currently owns the panel frame. `panel.screen` can lag while
    /// the cursor has already crossed to another display, so keep the selector's
    /// resolved display identity explicitly.
    private var positionedScreenID: CGDirectDisplayID?

    private(set) var isVisible = false
    private(set) var presentationStyle: OverlayPresentationStyle = .notchIsland

    private var latestTrack = Track.empty
    private var latestLines: [LyricLine] = []
    private var latestPosition: TimeInterval = 0
    private var latestAvailability: LyricsAvailability = .skipped
    private var latestStatus: String?
    private var latestSource: MusicPlayerSource?
    private var latestArtwork: NSImage?
    private var islandMode: IslandMode = .collapsed
    private var expandLocked = false
    private var appearance = OverlayAppearance.default
    private var screenPlacement: ScreenPlacement = .preferNotched
    private var verticalOffset: CGFloat = 0
    private var islandExtraWidth: CGFloat = 0
    private var lyricAccent: Color?
    private var translationText: String?
    private var isLoadingLyrics = false
    private var syncStatusText: String?
    private var trackOffsetSeconds: Double = 0
    private var hasTrackOffset = false

    var onToggleExpand: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onRefreshLyrics: (() -> Void)?
    var onNudgeTrackOffset: ((Double) -> Void)?
    var onResetTrackOffset: (() -> Void)?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPresentationStyle()
                self.reposition()
                self.render()
            }
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reposition()
                if self.isVisible {
                    self.panel?.orderFrontRegardless()
                }
            }
        }
    }

    func shutdown() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil
        stopMonitors()
        setVisible(false)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else {
            if visible { refreshMouseEventPassthrough() }
            return
        }
        isVisible = visible
        if visible {
            ensurePanel()
            refreshPresentationStyle()
            render()
            reposition()
            applyMousePolicy()
            startMonitors()
            panel?.orderFrontRegardless()
        } else {
            stopMonitors()
            panel?.orderOut(nil)
        }
    }

    func apply(
        appearance: OverlayAppearance,
        screenPlacement: ScreenPlacement,
        verticalOffset: Double,
        islandExtraWidth: Double = 0
    ) {
        self.appearance = appearance
        self.screenPlacement = screenPlacement
        self.verticalOffset = CGFloat(verticalOffset)
        self.islandExtraWidth = CGFloat(max(0, islandExtraWidth))
        refreshPresentationStyle()
        applyMousePolicy()
        if isVisible {
            render()
        }
        if isVisible { reposition() }
    }

    func update(
        track: Track,
        lines: [LyricLine],
        position: TimeInterval,
        lyricsAvailability: LyricsAvailability,
        statusMessage: String?,
        islandMode: IslandMode,
        expandLocked: Bool = false,
        playerSource: MusicPlayerSource? = nil,
        artwork: NSImage? = nil,
        lyricAccent: Color? = nil,
        translationText: String? = nil,
        isLoadingLyrics: Bool = false,
        syncStatusText: String? = nil,
        trackOffsetSeconds: Double = 0,
        hasTrackOffset: Bool = false
    ) {
        let layoutChanged = self.islandMode != islandMode || self.expandLocked != expandLocked
        latestTrack = track
        latestLines = lines
        latestPosition = position
        latestAvailability = lyricsAvailability
        latestStatus = statusMessage
        latestSource = playerSource
        latestArtwork = artwork
        self.lyricAccent = lyricAccent
        self.translationText = translationText
        self.isLoadingLyrics = isLoadingLyrics
        self.syncStatusText = syncStatusText
        self.trackOffsetSeconds = trackOffsetSeconds
        self.hasTrackOffset = hasTrackOffset
        self.islandMode = islandMode
        self.expandLocked = expandLocked
        if layoutChanged {
            applyMousePolicy()
        }
        if isVisible {
            render()
        }
    }

    // MARK: - Presentation style

    private func refreshPresentationStyle() {
        let screen = currentScreen()
        let hasNotch = screen.map { NotchGeometry.isNotchedDisplay($0) } ?? false
        presentationStyle = hasNotch ? .notchIsland : .floatingHUD
        // Floating HUD sits lower; notch mode rides above menu bar.
        if presentationStyle == .notchIsland {
            panel?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        } else {
            panel?.level = .floating
        }
    }

    // MARK: - Mouse policy

    private func applyMousePolicy() {
        refreshMouseEventPassthrough()
    }

    /// The panel canvas is always **expanded-sized** (for morph animation). When
    /// `ignoresMouseEvents == false`, that whole rectangle steals clicks from apps
    /// below — disastrous with 「維持展開」. Only accept mouse while the cursor is
    /// actually over the *visual* island; empty canvas always passes through.
    private func refreshMouseEventPassthrough() {
        guard let panel else { return }
        guard isVisible else {
            panel.ignoresMouseEvents = true
            return
        }

        // Keep receiving while a button is held (scrub / drag) even if the cursor
        // briefly leaves the hit rect.
        if !panel.ignoresMouseEvents, NSEvent.pressedMouseButtons != 0 {
            return
        }

        guard let screen = currentScreen() else {
            panel.ignoresMouseEvents = true
            return
        }
        let overIsland = interactiveScreenRect(on: screen).contains(NSEvent.mouseLocation)

        switch presentationStyle {
        case .notchIsland:
            // Collapsed: global monitors drive hover/click; panel stays pass-through.
            // Expanded: only the pill is interactive — never the transparent canvas.
            if islandMode == .expanded {
                panel.ignoresMouseEvents = !overIsland
            } else {
                panel.ignoresMouseEvents = true
            }
        case .floatingHUD:
            if islandMode == .expanded {
                panel.ignoresMouseEvents = !overIsland
            } else if appearance.clickThrough {
                panel.ignoresMouseEvents = true
            } else {
                panel.ignoresMouseEvents = !overIsland
            }
        }
    }

    private func startMonitors() {
        stopMonitors()

        moveMonitor = MouseEventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseMove() }
        }
        moveMonitor?.start()

        clickMonitor = MouseEventMonitor(mask: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseDown() }
        }
        clickMonitor?.start()
    }

    private func stopMonitors() {
        hoverOpenWork?.cancel()
        hoverOpenWork = nil
        moveMonitor?.stop()
        moveMonitor = nil
        clickMonitor?.stop()
        clickMonitor = nil
    }

    private func handleMouseMove() {
        guard isVisible, let screen = currentScreen() else { return }
        if screenPlacement == .mouseCursor,
           positionedScreenID != Self.displayID(for: screen)
        {
            // `.mouseCursor` is dynamic: crossing displays must update both the
            // frame and notch-vs-floating presentation, not only hover hit tests.
            refreshPresentationStyle()
            render()
            reposition()
        }
        // Always recompute pass-through so 「維持展開」 never blocks other apps.
        refreshMouseEventPassthrough()

        let inTarget = interactiveScreenRect(on: screen).contains(NSEvent.mouseLocation)

        // Cancel any pending work — expand / collapse fire immediately on edge.
        hoverOpenWork?.cancel()
        hoverOpenWork = nil

        if inTarget {
            // Snap open the moment the pointer enters the island.
            onHoverChanged?(true)
        } else {
            // Snap closed the moment the pointer leaves.
            onHoverChanged?(false)
        }
    }

    private func handleMouseDown() {
        guard isVisible, let screen = currentScreen() else { return }
        let loc = NSEvent.mouseLocation
        let target = interactiveScreenRect(on: screen)

        switch islandMode {
        case .collapsed:
            // Click on notch opens immediately (no dwell).
            if target.contains(loc) {
                hoverOpenWork?.cancel()
                hoverOpenWork = nil
                onHoverChanged?(true)
            }
        case .expanded:
            // Click outside collapses (unless 「維持展開」 is handled in AppModel).
            if !target.contains(loc) {
                hoverOpenWork?.cancel()
                hoverOpenWork = nil
                onHoverChanged?(false)
            }
        }
    }

    /// Hover / click target = **visual island**, not the full transparent panel canvas.
    private func interactiveScreenRect(on screen: NSScreen) -> CGRect {
        let canvas = windowFrame(for: screen)
        let visual = visualIslandSize(on: screen)
        let x = canvas.midX - visual.width / 2
        // AppKit: origin bottom-left; panel top is canvas.maxY.
        let y = canvas.maxY - visual.height
        return CGRect(x: x, y: y, width: visual.width, height: visual.height)
            .insetBy(dx: -10, dy: -8)
    }

    /// Drawn island size for the current mode (hit-testing + hover).
    /// Must match `NotchOverlayView` / `IslandVisualGeometry` so edge controls stay clickable.
    private func visualIslandSize(on screen: NSScreen) -> CGSize {
        IslandVisualGeometry.visualSize(
            presentation: presentationStyle,
            mode: islandMode,
            deviceNotch: screen.lyrinotchSize,
            islandExtraWidth: islandExtraWidth,
            showAdjacentLines: appearance.showAdjacentLines,
            hasTranslation: hasVisibleTranslation
        )
    }

    /// Transparent canvas large enough for the **expanded** island so SwiftUI can
    /// spring-morph without the NSPanel resizing (reference-app style silkiness).
    private func contentSize(on screen: NSScreen) -> CGSize {
        IslandVisualGeometry.contentSize(
            presentation: presentationStyle,
            deviceNotch: screen.lyrinotchSize,
            islandExtraWidth: islandExtraWidth,
            showAdjacentLines: appearance.showAdjacentLines,
            hasTranslation: hasVisibleTranslation
        )
    }

    private var hasVisibleTranslation: Bool {
        translationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    // MARK: - Panel

    private func ensurePanel() {
        if panel != nil { return }

        let screen = currentScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = windowFrame(for: screen)

        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let renderer = NotchOverlayRenderer(
            content: makeContent(
                deviceNotch: screen.lyrinotchSize,
                hasNotch: screen.hasPhysicalNotch,
                style: presentationStyle
            ),
            callbacks: makeCallbacks()
        )
        let hosting = renderer.hostingView
        if #available(macOS 13.0, *) {
            hosting.safeAreaRegions = []
        }
        // Required for SwiftUI materials (Liquid Glass) to sample desktop behind the panel.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.hitTestRect = { [weak self] in
            self?.contentHitRectInWindow() ?? .zero
        }
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = true

        self.panel = panel
        self.renderer = renderer
        refreshPresentationStyle()
    }

    private func render() {
        ensurePanel()
        let screen = currentScreen() ?? NSScreen.main
        let notch = screen?.lyrinotchSize ?? CGSize(width: 180, height: 32)
        let hasNotch = screen.map { NotchGeometry.isNotchedDisplay($0) } ?? false
        renderer?.update(makeContent(
            deviceNotch: notch,
            hasNotch: hasNotch,
            style: presentationStyle
        ))
    }

    private func makeContent(
        deviceNotch: CGSize,
        hasNotch: Bool,
        style: OverlayPresentationStyle
    ) -> NotchOverlayContent {
        NotchOverlayContent(
            track: latestTrack,
            lines: latestLines,
            position: latestPosition,
            lyricsAvailability: latestAvailability,
            appearance: appearance,
            statusMessage: latestStatus,
            islandMode: islandMode,
            deviceNotchSize: deviceNotch,
            hasPhysicalNotch: hasNotch,
            presentationStyle: style,
            expandLocked: expandLocked,
            playerSource: latestSource,
            artwork: latestArtwork,
            lyricAccent: lyricAccent,
            islandExtraWidth: islandExtraWidth,
            translationText: translationText,
            isLoadingLyrics: isLoadingLyrics,
            syncStatusText: syncStatusText,
            trackOffsetSeconds: trackOffsetSeconds,
            hasTrackOffset: hasTrackOffset
        )
    }

    private func makeCallbacks() -> NotchOverlayCallbacks {
        NotchOverlayCallbacks(
            onToggleExpand: { [weak self] in self?.onToggleExpand?() },
            onPlayPause: { [weak self] in self?.onPlayPause?() },
            onNext: { [weak self] in self?.onNext?() },
            onPrevious: { [weak self] in self?.onPrevious?() },
            onSeek: { [weak self] seconds in self?.onSeek?(seconds) },
            onRefreshLyrics: { [weak self] in self?.onRefreshLyrics?() },
            onNudgeTrackOffset: { [weak self] delta in self?.onNudgeTrackOffset?(delta) },
            onResetTrackOffset: { [weak self] in self?.onResetTrackOffset?() }
        )
    }

    func reposition() {
        guard let panel, let screen = currentScreen() else { return }
        // Canvas is always expanded-sized and top-centered; do not animate frame on mode change.
        panel.setFrame(windowFrame(for: screen), display: true)
        positionedScreenID = Self.displayID(for: screen)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Screen frame of the transparent canvas (expanded size), centered on the notch.
    private func windowFrame(for screen: NSScreen) -> NSRect {
        let size = contentSize(on: screen)
        let x = screen.frame.midX - size.width / 2
        switch presentationStyle {
        case .notchIsland:
            let nudge = min(max(verticalOffset, -4), 12) * 0.25
            let y = screen.frame.maxY - size.height - nudge
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        case .floatingHUD:
            let gap: CGFloat = 4 + min(max(verticalOffset, 0), 20)
            let top = screen.visibleFrame.maxY - gap
            return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
        }
    }

    private func currentScreen() -> NSScreen? {
        ScreenSelector.screen(for: screenPlacement)
    }

    /// Hit area in **window** coordinates (origin bottom-left) for the **visual island only**.
    /// Empty canvas around the island stays click-through via PassThroughHostingView.
    private func contentHitRectInWindow() -> CGRect {
        guard let panel, let screen = currentScreen() else { return .zero }
        let visual = visualIslandSize(on: screen)
        let pw = panel.frame.width
        let ph = panel.frame.height
        let x = (pw - visual.width) / 2
        let y = ph - visual.height // top-aligned
        return CGRect(x: x, y: y, width: visual.width, height: visual.height)
    }
}
