import AppKit
import SwiftUI
import LyrinotchCore

/// Menu-bar agent UI with notch island overlay + dedicated Settings window.
struct LyrinotchGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        // `image:` reads MenuBarIcon from Assets.car (compiled by package-app.sh).
        // Label fallback uses NSImage / embedded PNG when running via `swift run`.
        MenuBarExtra("Lyrinotch", image: "MenuBarIcon") {
            MenuBarExtraView(
                trackTitle: model.menuTrackTitle,
                playbackGlyph: model.menuPlaybackGlyph,
                lyricsLabel: model.menuLyricsLabel,
                islandModeLabel: model.islandModeLabel,
                isOverlayVisible: model.isOverlayVisible,
                isIslandExpanded: model.effectiveIslandMode == .expanded,
                lastError: model.lastError ?? model.playbackWarning,
                onToggleOverlay: { model.toggleOverlay() },
                onToggleExpand: { model.toggleExpandFromMenu() },
                onRefresh: { model.refreshNow() },
                onSearchLyrics: {
                    openUtilityWindow(id: "lyrics-search", title: L10n.t("search.title"))
                },
                onOpenSettings: {
                    openUtilityWindow(id: "settings", title: L10n.t("window.settings"))
                },
                onOpenAbout: {
                    openUtilityWindow(id: "about", title: L10n.t("about.window_title"))
                },
                onOpenDonate: {
                    openUtilityWindow(id: "support", title: L10n.t("support.window_title"))
                },
                onReportBug: { _ = AppInfo.openBugReport() },
                onQuit: { model.quit() }
            )
            .id(model.preferredLanguage)
        }
        .menuBarExtraStyle(.window)

        Window(L10n.t("window.settings"), id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.t("search.title"), id: "lyrics-search") {
            LyricsSearchView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.t("tap_sync.title"), id: "tap-sync") {
            TapSyncView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.t("about.window_title"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.t("support.window_title"), id: "support") {
            SupportView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window(L10n.t("legal.disclaimer_title"), id: "disclaimer") {
            DisclaimerView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var utilityWindowTitles: Set<String> {
        [
            L10n.t("window.settings"),
            L10n.t("search.title"),
            L10n.t("tap_sync.title"),
            L10n.t("about.window_title"),
            L10n.t("support.window_title"),
            L10n.t("legal.disclaimer_title"),
            // Legacy Chinese titles (open before language change).
            "Lyrinotch 設定",
            "關於 Lyrinotch",
            "支持 Lyrinotch",
            "免責聲明",
            "Disclaimer"
        ]
    }

    /// Bring up a small utility window for an accessory (menu-bar) app.
    @MainActor
    private func openUtilityWindow(id: String, title: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let stillOpen = NSApp.windows.contains {
                ($0.identifier?.rawValue == id || $0.title == title) && $0.isVisible
            }
            if !stillOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == title {
                window.isReleasedWhenClosed = false
                UtilityWindowCloseObserverRegistry.shared.observe(
                    window: window,
                    utilityWindowTitles: utilityWindowTitles
                )
            }
        }
    }
}

/// Owns exactly one close observer per long-lived SwiftUI utility window.
@MainActor
private final class UtilityWindowCloseObserverRegistry {
    static let shared = UtilityWindowCloseObserverRegistry()
    private var tokens: [ObjectIdentifier: NSObjectProtocol] = [:]

    func observe(window: NSWindow, utilityWindowTitles: Set<String>) {
        let identifier = ObjectIdentifier(window)
        guard tokens[identifier] == nil else { return }

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self else { return }
                defer { self.removeObserver(for: identifier) }
                guard let window else { return }
                let otherOpen = NSApp.windows.contains {
                    $0.isVisible
                        && utilityWindowTitles.contains($0.title)
                        && $0 !== window
                }
                if !otherOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        tokens[identifier] = token
    }

    private func removeObserver(for identifier: ObjectIdentifier) {
        guard let token = tokens.removeValue(forKey: identifier) else { return }
        NotificationCenter.default.removeObserver(token)
    }
}

/// Windows opened from another settings window bypass `openUtilityWindow`.
/// Re-evaluate accessory mode when those child views disappear so the app does
/// not leave a Dock icon behind after the last utility window closes.
@MainActor
enum UtilityWindowActivation {
    static func restoreAccessoryModeIfNeeded() {
        Task { @MainActor in
            await Task.yield()
            let hasVisibleUtilityWindow = NSApp.windows.contains {
                $0.isVisible && $0.canBecomeMain
            }
            if !hasVisibleUtilityWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
