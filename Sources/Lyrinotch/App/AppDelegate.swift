import AppKit

/// Ensures polling / hotkeys start at app launch (not only when the menu opens).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
