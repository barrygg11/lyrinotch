# Security

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems that could harm users.

Email **barry.lai@icloud.com** with:

- Description and impact
- Steps to reproduce (if any)
- Affected version / commit if known

You should receive an acknowledgment when the maintainer is available.

## Scope notes

- Lyrinotch uses **local AppleScript** against Spotify / Music and **HTTPS** for configured online features. Lyric lookup can contact LRCLIB, NetEase, or lyrics.ovh; optional translation uses MyMemory, update checks use GitHub, and remote artwork is fetched from the player-provided image URL. It does not implement Spotify/Apple OAuth.
- Treat Automation permission as sensitive: only grant it to apps you trust.
- Microphone-based lyric timing calibration is **off by default** and runs only after the user enables it or starts a manual recalibration. Raw microphone samples are reduced to an energy/onset envelope in memory, are not written to disk, and are not sent over the network. The resulting numeric offset, confidence, lyric fingerprint, and audio-route identity may be persisted locally.
- Treat Microphone permission as sensitive. It is optional; lyric timing can be adjusted manually without granting it.
- Local LRC import is explicitly user-initiated, accepts only bounded `.lrc` files, releases security-scoped access after parsing, and does not upload or retain the original file path. Tap Sync stores only the local editing project and generated timeline.
- Packaged builds from this repo are **ad-hoc signed** unless you re-sign them yourself—verify the source you build from.
