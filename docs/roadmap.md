# Lyrinotch roadmap (historical + notes)

This document is a **product history**, not a commitment. Prefer the root [README](../README.md) for current behavior.

## Done (shipped in tree)

- [x] Spotify + Apple Music now-playing via AppleScript
- [x] Multi-source lyrics with provider fallback, TTL negative cache, and bounded LRCLIB requests
- [x] Notch island (collapsed = housing only; expand on hover) / floating HUD
- [x] Menu bar agent, settings, localization (zh-Hant / Hans / en / ja)
- [x] Preferences, hotkeys, launch at login (packaged app)
- [x] Package script (`scripts/package-app.sh`, ad-hoc sign)
- [x] In-app disclaimer + MIT license
- [x] Strict-concurrency / Release / coverage-gated CI
- [x] Signature- and Team-ID-verified updater for Developer ID builds; manual fallback for ad-hoc builds

## Possible later

- [ ] Apple Developer ID sign + notarize
- [ ] Notarize Developer ID release artifacts
- [ ] Continue improving provider matching with recorded edge cases
- [ ] CI package artifact (unsigned) for testers

## Open product questions

1. How far to go on lyric matching edge cases (multi-language titles).
2. Whether notarized distribution is worth the Apple program cost.
3. Keeping LRCLIB usage polite (rate limits, User-Agent).
