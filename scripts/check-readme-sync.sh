#!/usr/bin/env bash
# Keep the four public README translations structurally synchronized.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

READMES=(
  "README.md"
  "README.zh-Hant.md"
  "README.zh-Hans.md"
  "README.ja.md"
)
LANGUAGE_NAV='[English](README.md) | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md)'

fail() {
  echo "error: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" Resources/Info.plist 2>/dev/null
}

extract_bash_commands() {
  awk '
    /^[[:space:]]*```bash[[:space:]]*$/ {
      inside_bash = 1
      next
    }
    inside_bash && /^[[:space:]]*```[[:space:]]*$/ {
      inside_bash = 0
      next
    }
    inside_bash {
      candidate = $0
      sub(/^[[:space:]]+/, "", candidate)
      sub(/[[:space:]]+$/, "", candidate)
      if (candidate == "" || candidate ~ /^#/) {
        next
      }
      print $0
    }
  ' "$1"
}

[[ -x /usr/libexec/PlistBuddy ]] \
  || fail "required command not found: /usr/libexec/PlistBuddy"

SOURCE_VERSION="$(plist_value CFBundleShortVersionString)"
SOURCE_BUILD="$(plist_value CFBundleVersion)"
[[ -n "$SOURCE_VERSION" ]] || fail "source version is empty"
[[ "$SOURCE_BUILD" =~ ^[0-9]+$ ]] || fail "source build must be an integer"

REFERENCE_REVISION=""
REFERENCE_SECTIONS=""
REFERENCE_BASH_COMMANDS=""
REFERENCE_BASH_COMMANDS_SET=false

for readme in "${READMES[@]}"; do
  [[ -f "$readme" ]] || fail "missing $readme"
  grep -Fxq "$LANGUAGE_NAV" "$readme" \
    || fail "$readme is missing the shared language navigation"

  [[ "$(grep -Ec '^<!-- readme-revision: [0-9]+ -->$' "$readme")" -eq 1 ]] \
    || fail "$readme must contain exactly one readme-revision marker"
  revision="$(sed -nE 's/^<!-- readme-revision: ([0-9]+) -->$/\1/p' "$readme")"

  [[ "$(grep -Ec '^<!-- source-version: .* -->$' "$readme")" -eq 1 ]] \
    || fail "$readme must contain exactly one source-version marker"
  [[ "$(grep -Ec '^<!-- source-build: .* -->$' "$readme")" -eq 1 ]] \
    || fail "$readme must contain exactly one source-build marker"

  grep -Fxq "<!-- source-version: $SOURCE_VERSION -->" "$readme" \
    || fail "$readme source version does not match Resources/Info.plist"
  grep -Fxq "<!-- source-build: $SOURCE_BUILD -->" "$readme" \
    || fail "$readme source build does not match Resources/Info.plist"

  sections="$(sed -nE 's/^<!-- section: ([a-z0-9-]+) -->$/\1/p' "$readme")"
  [[ -n "$sections" ]] || fail "$readme has no section markers"
  bash_commands="$(extract_bash_commands "$readme")"

  if [[ -z "$REFERENCE_REVISION" ]]; then
    REFERENCE_REVISION="$revision"
    REFERENCE_SECTIONS="$sections"
  else
    [[ "$revision" == "$REFERENCE_REVISION" ]] \
      || fail "$readme revision $revision does not match $REFERENCE_REVISION"
    [[ "$sections" == "$REFERENCE_SECTIONS" ]] \
      || fail "$readme section order does not match README.md"
  fi

  if [[ "$REFERENCE_BASH_COMMANDS_SET" == false ]]; then
    REFERENCE_BASH_COMMANDS="$bash_commands"
    REFERENCE_BASH_COMMANDS_SET=true
  else
    [[ "$bash_commands" == "$REFERENCE_BASH_COMMANDS" ]] \
      || fail "$readme bash command sequence does not match README.md"
  fi

  while IFS= read -r markdown_link; do
    target="${markdown_link#](}"
    target="${target%)}"
    case "$target" in
      ""|\#*|http://*|https://*|mailto:*) continue ;;
    esac
    target="${target%%#*}"
    [[ -e "$(dirname "$readme")/$target" ]] \
      || fail "$readme contains a missing local link: $target"
  done < <(grep -oE '\]\([^)]+\)' "$readme" || true)
done

README_COUNT="${#READMES[@]}"
echo "README sync OK: $README_COUNT languages, revision $REFERENCE_REVISION, source $SOURCE_VERSION ($SOURCE_BUILD)"
