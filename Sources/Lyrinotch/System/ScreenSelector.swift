import AppKit
import LyrinotchCore

/// Picks which `NSScreen` should host the overlay.
enum ScreenSelector {
    static func screen(for placement: ScreenPlacement) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        switch placement {
        case .mouseCursor:
            let mouse = NSEvent.mouseLocation
            if let hit = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return hit
            }
            return NSScreen.main ?? screens.first

        case .specific(let displayID, let displayName):
            if let match = screens.first(where: { $0.lyrinotchDisplayID == displayID }) {
                return match
            }
            // ID can change after sleep / cable swap — fall back to last known name.
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let byName = screens.first(where: { $0.localizedName == trimmed })
            {
                return byName
            }
            return NSScreen.main ?? screens.first

        case .mainDisplay:
            return NSScreen.main ?? screens.first

        case .preferNotched:
            if let notched = screens.first(where: NotchGeometry.isNotchedDisplay) {
                return notched
            }
            if let builtIn = screens.first(where: { $0.isBuiltinDisplay }) {
                return builtIn
            }
            if let builtIn = screens.first(where: isBuiltInName) {
                return builtIn
            }
            return NSScreen.main ?? screens.first
        }
    }

    private static func isBuiltInName(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName.lowercased()
        return name.contains("built-in")
            || name.contains("color lcd")
            || name.contains("內建")
            || name.contains("内建")
    }
}

extension NSScreen {
    /// `CGDirectDisplayID` for persistence / picker tags.
    var lyrinotchDisplayID: UInt32 {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return number.uint32Value
    }

    /// Picker label: system localized name, with a short role hint when useful.
    func lyrinotchPickerLabel(modelName: String?) -> String {
        let base = DisplayNameFormatter.baseName(
            rawName: localizedName,
            displayID: lyrinotchDisplayID,
            isBuiltIn: isBuiltinDisplay,
            localizedBuiltInName: L10n.t("screen.builtin"),
            modelName: modelName
        )
        return DisplayNameFormatter.pickerLabel(
            baseName: base,
            isMain: self == NSScreen.main,
            localizedMainRole: L10n.t("screen.hint_main")
        )
    }

    /// Heuristic: menu bar + dock both gone usually means a fullscreen space.
    var lyrinotchLooksFullscreenOccupied: Bool {
        let menuBarH = frame.maxY - visibleFrame.maxY
        let dockH = visibleFrame.minY - frame.minY
        return menuBarH < 2 && dockH < 2
    }
}
