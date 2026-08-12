# Contributing to Lyrinotch

Thanks for your interest. This is a small personal project; focused PRs are welcome.

## Development

```bash
swift build
swift test
swift run Lyrinotch
```

Before opening a PR, run the same important gates as CI:

```bash
swift test --enable-code-coverage -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency -Xswiftc -warnings-as-errors
bash scripts/check-coverage.sh 25
swift build -c release
```

- Prefer changes under `LyrinotchCore` when logic can be unit-tested without AppKit UI.
- Match existing style (Swift, no drive-by refactors).
- Add or update tests for parsers, matching, and preference clamping when you touch those areas.

## Pull requests

1. Describe **what** and **why**.
2. Note macOS version tested if UI-related.
3. Do not commit `.build/`, `dist/`, secrets, or personal absolute paths.

## Issues

Include:

- macOS version / Apple Silicon vs Intel
- Spotify vs Music
- Steps to reproduce
- Output of **Copy version info** from Settings → About (if possible)

## License

By contributing, you agree your contributions are licensed under the MIT License (same as the project).
