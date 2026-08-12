import AppKit
import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Samples a readable accent color from album artwork for lyric tinting.
public enum ArtworkColorSampler {
    /// Average a downscaled bitmap; prefer mid-saturation tones that stay legible on black.
    public static func lyricAccent(from image: NSImage?) -> Color? {
        guard let ns = sampleNSColor(from: image) else { return nil }
        return Color(nsColor: ns)
    }

    public static func sampleNSColor(from image: NSImage?) -> NSColor? {
        guard let image else { return nil }
        let target = NSSize(width: 16, height: 16)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        var rSum = 0.0, gSum = 0.0, bSum = 0.0, weight = 0.0
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                guard a > 0.2 else { continue }
                // Weight mid-brightness pixels more (skip pure black / near-white).
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                guard lum > 0.12, lum < 0.92 else { continue }
                let sat = max(r, g, b) - min(r, g, b)
                let wgt = Double(0.35 + sat * 1.4)
                rSum += Double(r) * wgt
                gSum += Double(g) * wgt
                bSum += Double(b) * wgt
                weight += wgt
            }
        }
        guard weight > 0 else { return nil }

        var r = rSum / weight
        var g = gSum / weight
        var b = bSum / weight
        // Lift very dark accents so lyrics stay readable on the black island.
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if lum < 0.45 {
            let boost = (0.55 - lum) * 0.85
            r = min(1, r + boost)
            g = min(1, g + boost)
            b = min(1, b + boost)
        }
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}
#endif
