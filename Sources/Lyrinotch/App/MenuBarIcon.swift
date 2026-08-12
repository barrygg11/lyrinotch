import AppKit
import SwiftUI

/// Loads the Lyrinotch menu-bar glyph as a template `NSImage`.
///
/// Probes multiple locations because SPM's generated `Bundle.module` path does
/// not always match a packaged `.app` layout.
enum MenuBarIcon {
    private static let resourceName = "MenuBarIcon"
    private static let pointSize = NSSize(width: 18, height: 18)

    /// Cached once; MenuBarExtra evaluates the label frequently.
    private static let cached: NSImage = {
        let image: NSImage
        // 1) Assets.car in the main bundle (package-app.sh compiles this).
        if let named = NSImage(named: NSImage.Name(resourceName)) {
            image = prepared(named)
        } else if let loaded = loadFromDisk() {
            // 2) Loose PNG / SPM resource bundle.
            image = prepared(loaded)
        } else if let embedded = EmbeddedMenuBarIcon.nsImage() {
            // 3) Base64 baked into the binary.
            image = prepared(embedded)
        } else {
            let fallback = NSImage(
                systemSymbolName: "capsule.portrait.fill",
                accessibilityDescription: "Lyrinotch"
            ) ?? NSImage(size: pointSize)
            image = prepared(fallback)
        }
        // Register under a known name for any late NSImage(named:) lookups.
        image.setName(NSImage.Name(resourceName))
        return image
    }()

    static func nsImage() -> NSImage { cached }

    static var didLoadFromDisk: Bool { loadFromDisk() != nil }

    // MARK: - Disk load

    private static func loadFromDisk() -> NSImage? {
        for url in candidatePNGURLs() {
            guard let image = NSImage(contentsOf: url) else { continue }
            let twoX = url.deletingLastPathComponent()
                .appendingPathComponent("\(resourceName)@2x.png")
            if let data = try? Data(contentsOf: twoX),
               let rep = NSBitmapImageRep(data: data) {
                image.addRepresentation(rep)
            }
            return image
        }
        return nil
    }

    private static func candidatePNGURLs() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url else { return }
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return }
            guard FileManager.default.fileExists(atPath: path) else { return }
            seen.insert(path)
            urls.append(url)
        }

        func addFromBundle(_ bundle: Bundle?) {
            guard let bundle else { return }
            add(bundle.url(forResource: resourceName, withExtension: "png"))
            if let path = bundle.path(forResource: resourceName, ofType: "png") {
                add(URL(fileURLWithPath: path))
            }
            add(bundle.bundleURL.appendingPathComponent("\(resourceName).png"))
            // Inside copied Assets.xcassets (SPM does not compile to Assets.car).
            add(
                bundle.bundleURL
                    .appendingPathComponent("Assets.xcassets")
                    .appendingPathComponent("\(resourceName).imageset")
                    .appendingPathComponent("\(resourceName).png")
            )
        }

        // Avoid touching Bundle.module first — its static init can fatalError if
        // both the .app-root and hardcoded build paths are missing. Prefer main
        // bundle files that package-app.sh always installs.
        if let resourceURL = Bundle.main.resourceURL {
            add(resourceURL.appendingPathComponent("\(resourceName).png"))
            add(
                resourceURL
                    .appendingPathComponent("Assets.xcassets")
                    .appendingPathComponent("\(resourceName).imageset")
                    .appendingPathComponent("\(resourceName).png")
            )
            addFromBundle(Bundle(url: resourceURL.appendingPathComponent("Lyrinotch_Lyrinotch.bundle")))
        }

        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            addFromBundle(Bundle(url: exeDir.appendingPathComponent("Lyrinotch_Lyrinotch.bundle")))
            add(exeDir.appendingPathComponent("\(resourceName).png"))
        }

        addFromBundle(Bundle.main)

        // SPM resource bundles next to the process (covers `swift run` without
        // touching generated Bundle.module, which can fatalError when both its
        // hardcoded paths are missing).
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            // e.g. .build/arm64-apple-macosx/debug/Lyrinotch_Lyrinotch.bundle
            addFromBundle(Bundle(url: exeDir.appendingPathComponent("Lyrinotch_Lyrinotch.bundle")))
            // Sometimes the resource bundle sits one level up from a nested layout.
            addFromBundle(
                Bundle(url: exeDir
                    .deletingLastPathComponent()
                    .appendingPathComponent("Lyrinotch_Lyrinotch.bundle"))
            )
        }

        // Absolute paths used by local `swift build` (debug + release).
        let homeBuild = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/
            .deletingLastPathComponent() // Lyrinotch/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".build")
        for config in ["debug", "release"] {
            let bundleURL = homeBuild
                .appendingPathComponent("arm64-apple-macosx")
                .appendingPathComponent(config)
                .appendingPathComponent("Lyrinotch_Lyrinotch.bundle")
            addFromBundle(Bundle(url: bundleURL))
            add(bundleURL.appendingPathComponent("\(resourceName).png"))
        }

        return urls
    }

    private static func prepared(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = pointSize
        return image
    }
}

/// Menu bar label: template glyph sized by the `NSImage` point size (18×18).
/// Avoid `.resizable()` here — it often blanks custom MenuBarExtra icons.
struct MenuBarIconLabel: View {
    var body: some View {
        // `Label` + iconOnly is the most reliable MenuBarExtra custom-image path.
        Label {
            Text("Lyrinotch")
        } icon: {
            Image(nsImage: MenuBarIcon.nsImage())
                .renderingMode(.template)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Lyrinotch")
    }
}
