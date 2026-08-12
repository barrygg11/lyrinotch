#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$PROJECT_ROOT/scripts/check-release-notes.sh"
FIXTURE_TEMPLATE="$PROJECT_ROOT/Tests/Fixtures/ReleaseNotes/valid"
TEST_ROOT="$(mktemp -d)"
FIXTURE_ROOT=""

trap 'rm -rf "$TEST_ROOT"' EXIT

fresh_fixture() {
  FIXTURE_ROOT="$(mktemp -d "$TEST_ROOT/release-notes.XXXXXX")"
  cp -R "$FIXTURE_TEMPLATE/." "$FIXTURE_ROOT/"
}

expect_pass() {
  local stderr_path="$FIXTURE_ROOT/stderr"

  if ! LYRINOTCH_RELEASE_NOTES_ROOT="$FIXTURE_ROOT" bash "$CHECKER" 2>"$stderr_path"; then
    echo "error: expected acceptance: $1" >&2
    cat "$stderr_path" >&2
    exit 1
  fi
}

expect_failure() {
  local stderr_path="$FIXTURE_ROOT/stderr"
  local first_stderr_line=""

  if LYRINOTCH_RELEASE_NOTES_ROOT="$FIXTURE_ROOT" bash "$CHECKER" 2>"$stderr_path"; then
    echo "error: expected rejection: $1" >&2
    exit 1
  fi
  IFS= read -r first_stderr_line < "$stderr_path" || true
  if [[ "$first_stderr_line" != error:* ]]; then
    echo "error: rejection did not write an error: message: $1" >&2
    cat "$stderr_path" >&2
    exit 1
  fi
}

expect_integration() {
  local relative_path="$1"
  local invocation="$2"

  if ! grep -Fq "$invocation" "$PROJECT_ROOT/$relative_path"; then
    echo "error: expected $relative_path to invoke: $invocation" >&2
    exit 1
  fi
}

fresh_fixture
expect_pass "valid fixture"

fresh_fixture
rm "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "missing notes file"

fresh_fixture
sed -i '' '1c\
Not a title
2i\
# Lyrinotch 1.2.3
' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "H1 moved away from line 1"

fresh_fixture
sed -i '' '1c\
# Lyrinotch 9.9.9
' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "wrong H1 version"

fresh_fixture
sed -i '' '2i\
# Lyrinotch 1.2.3
' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "duplicate H1"

fresh_fixture
printf '\n#\tAdditional heading\n' >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "tab-separated additional H1"

fresh_fixture
sed -i '' '3c\
> Build 5 · macOS 14+
' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "wrong build metadata"

fresh_fixture
sed -i '' '5d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "missing summary line"

fresh_fixture
sed -i '' '/^## Install or update$/d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "missing Install or update"

fresh_fixture
printf '\n## Install or update\n\n1. Repeat installation.\n' >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "duplicate Install or update"

fresh_fixture
printf '\n## Other\n\n- Unknown section.\n' >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "unknown H2"

fresh_fixture
printf '\n## Improved\n\n- Added after Fixed.\n' >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "out-of-order H2"

fresh_fixture
sed -i '' '/^- Keeps playback controls available while paused\.$/d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "empty included change section"

fresh_fixture
sed -i '' '/^## Highlights$/,+2d; /^## Fixed$/,+2d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "no change section"

fresh_fixture
sed -i '' -E '/^[0-9]+\. /d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "Install or update without a numbered step"

fresh_fixture
sed -i '' 's/Lyrinotch-1\.2\.3\.dmg/Lyrinotch-9.9.9.dmg/' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "wrong DMG version"

fresh_fixture
sed -i '' 's/Lyrinotch-1\.2\.3\.dmg/Installer.dmg/' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
printf '\n- Archive **Lyrinotch-1.2.3.dmg**.\n' >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "correct DMG outside Install or update"

fresh_fixture
sed -i '' '/^- Recheck Automation access if macOS asks again\.$/d' "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
expect_failure "empty After updating"

for marker in TBD TODO WIP; do
  fresh_fixture
  printf '\n%s\n' "$marker" >> "$FIXTURE_ROOT/docs/release-notes-1.2.3.md"
  expect_failure "literal $marker marker"
done

expect_integration ".github/workflows/ci.yml" "bash scripts/test-release-notes-checker.sh"
expect_integration ".github/workflows/ci.yml" "bash scripts/check-release-notes.sh"
expect_integration "scripts/create-dmg.sh" 'bash "$ROOT/scripts/check-release-notes.sh"'
expect_integration "docs/releasing.md" "bash scripts/check-release-notes.sh"

echo "release notes checker tests OK: valid fixture accepted; all negative cases rejected"
