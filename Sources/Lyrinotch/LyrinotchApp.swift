import Foundation

/// Process entry: GUI menu-bar app by default; CLI with `--cli` / `--once`.
@main
struct LyrinotchBootstrap {
    static func main() {
        let args = ProcessInfo.processInfo.arguments
        if UpdateInstallerHelper.runIfRequested(arguments: args) {
            return
        }
        let cliMode =
            args.contains("--cli")
            || args.contains("--once")
            || args.contains("--interval-ms")
            || args.contains("--help")
            || args.contains("-h")

        if args.contains("--help") || args.contains("-h") {
            printHelp()
            return
        }

        if cliMode {
            CLIRunner.runSync(arguments: args)
            return
        }

        // Menu bar + notch overlay (SwiftUI App lifecycle).
        LyrinotchGUIApp.main()
    }

    private static func printHelp() {
        print(
            """
            Lyrinotch — Spotify / Apple Music lyrics near the MacBook notch

            Usage:
              swift run Lyrinotch              Start menu-bar app + notch overlay
              swift run Lyrinotch --cli        Headless terminal poller
              swift run Lyrinotch --once       One-shot CLI snapshot
              swift run Lyrinotch --interval-ms 500

              ./scripts/package-app.sh        Build dist/Lyrinotch.app
              open dist/Lyrinotch.app

            Menu bar (繁中):
              • 顯示/隱藏浮層（⌘⇧L）
              • 收合/展開島（⌘⇧E）· 維持展開 · 切歌短暫展開
              • 點擊穿透、透明度、字級、偏移、螢幕
              • 開機啟動（需打包後的 .app）

            Permissions:
              System Settings → Privacy & Security → Automation
              Allow your terminal (or Lyrinotch.app) to control Spotify and Music.
            """
        )
    }
}
