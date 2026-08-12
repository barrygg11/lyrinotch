import AppKit
import CoreGraphics
import LyrinotchCore

/// Hardware notch geometry from public `NSScreen` APIs (same approach as vibe-notch).
enum NotchGeometry {
    /// Pixel-style notch size (matches vibe-notch `NSScreen.notchSize`).
    static func notchSize(on screen: NSScreen) -> CGSize {
        guard screen.safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 32)
        }
        let notchHeight = max(screen.safeAreaInsets.top, 24)
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        if left > 0, right > 0 {
            // Match vibe-notch / boring.notch: +4pt calibration against the camera housing.
            let width = screen.frame.width - left - right + 4
            return CGSize(
                width: max(120, min(width, screen.frame.width * 0.4)),
                height: notchHeight
            )
        }
        return CGSize(width: 180, height: notchHeight)
    }

    static func topChromeHeight(on screen: NSScreen) -> CGFloat {
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let safeTop = screen.safeAreaInsets.top
        let auxHeight = max(
            screen.auxiliaryTopLeftArea?.height ?? 0,
            screen.auxiliaryTopRightArea?.height ?? 0
        )
        return max(menuBar, safeTop, auxHeight, 24)
    }

    static func band(on screen: NSScreen) -> NotchBand? {
        band(
            screenFrame: screen.frame,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }

    static func band(
        screenFrame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        safeAreaTop: CGFloat
    ) -> NotchBand? {
        NotchGeometryLogic.band(
            screenFrame: screenFrame,
            auxiliaryTopLeft: auxiliaryTopLeft,
            auxiliaryTopRight: auxiliaryTopRight,
            safeAreaTop: safeAreaTop
        )
    }

    /// Notch hit target in **global screen coordinates** (for event monitors).
    static func notchHitRect(on screen: NSScreen, padding: CGFloat = 8) -> CGRect {
        let size = notchSize(on: screen)
        let rect = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.insetBy(dx: -padding, dy: -padding / 2)
    }

    /// Expanded panel rect in global coordinates (top-centered, grows downward from notch).
    static func openedHitRect(on screen: NSScreen, size: CGSize) -> CGRect {
        // Slightly taller default so title below the housing stays clickable.
        let h = max(size.height, 180)
        let w = size.width
        return CGRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.maxY - h,
            width: w,
            height: h
        )
    }

    static func isNotchedDisplay(_ screen: NSScreen) -> Bool {
        if band(on: screen)?.isHardwareNotch == true { return true }
        return screen.safeAreaInsets.top > 0
    }
}

extension NSScreen {
    var lyrinotchSize: CGSize { NotchGeometry.notchSize(on: self) }
    var hasPhysicalNotch: Bool { safeAreaInsets.top > 0 }

    var isBuiltinDisplay: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(number) != 0
    }
}
