#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_NOTES_ROOT="${LYRINOTCH_RELEASE_NOTES_ROOT:-$PROJECT_ROOT}"

fail() {
  echo "error: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$RELEASE_NOTES_ROOT/Resources/Info.plist" 2>/dev/null
}

section_requires_bullet() {
  case "$1" in
    Highlights|Improved|Fixed|After\ updating|Known\ issues) return 0 ;;
    *) return 1 ;;
  esac
}

[[ -x /usr/libexec/PlistBuddy ]] \
  || fail "required command not found: /usr/libexec/PlistBuddy"
[[ -f "$RELEASE_NOTES_ROOT/Resources/Info.plist" ]] \
  || fail "missing Resources/Info.plist"

VERSION="$(plist_value CFBundleShortVersionString)" \
  || fail "could not read CFBundleShortVersionString"
BUILD="$(plist_value CFBundleVersion)" \
  || fail "could not read CFBundleVersion"
MINIMUM_MACOS="$(plist_value LSMinimumSystemVersion)" \
  || fail "could not read LSMinimumSystemVersion"
[[ -n "$VERSION" && -n "$BUILD" && -n "$MINIMUM_MACOS" ]] \
  || fail "release metadata is empty"

NOTES_PATH="$RELEASE_NOTES_ROOT/docs/release-notes-$VERSION.md"
[[ -f "$NOTES_PATH" ]] || fail "missing $NOTES_PATH"

EXPECTED_MINIMUM_MACOS="$(printf '%s' "$MINIMUM_MACOS" | sed 's/\.0$//')"
[[ "$(sed -n '1p' "$NOTES_PATH")" == "# Lyrinotch $VERSION" ]] \
  || fail "line 1 must be # Lyrinotch $VERSION"

H1_COUNT="$(awk '/^#[[:space:]]/ { count++ } END { print count + 0 }' "$NOTES_PATH")"
[[ "$H1_COUNT" -eq 1 ]] || fail "release notes must contain one H1"

[[ "$(sed -n '3p' "$NOTES_PATH")" == "> Build $BUILD · macOS $EXPECTED_MINIMUM_MACOS+" ]] \
  || fail "line 3 metadata does not match Info.plist"

SUMMARY_LINE="$(sed -n '5p' "$NOTES_PATH")"
[[ -n "$SUMMARY_LINE" ]] || fail "line 5 must contain a summary"
[[ ! "$SUMMARY_LINE" =~ ^# ]] || fail "line 5 summary cannot be a heading"
[[ ! "$SUMMARY_LINE" =~ ^[-*+][[:space:]] ]] || fail "line 5 summary cannot be a list item"
[[ ! "$SUMMARY_LINE" =~ ^[0-9]+\.[[:space:]] ]] || fail "line 5 summary cannot be a list item"
[[ ! "$SUMMARY_LINE" =~ ^\> ]] || fail "line 5 summary cannot be a quote"
[[ ! "$SUMMARY_LINE" =~ ^\`\`\` ]] || fail "line 5 summary cannot be a code fence"

grep -Eiq '(^|[^[:alnum:]_])(TBD|TODO|WIP)($|[^[:alnum:]_])' "$NOTES_PATH" \
  && fail "release notes contain a placeholder marker"

SECTION_NAMES=()
SECTION_BULLETS=()
SECTION_STEPS=()
SECTION_EXACT_DMG=()
PREVIOUS_ORDER=0
CURRENT_SECTION=-1
LINE_NUMBER=0

while IFS= read -r line || [[ -n "$line" ]]; do
  LINE_NUMBER=$((LINE_NUMBER + 1))

  if [[ "$line" =~ ^##[[:space:]](.+)$ ]]; then
    if [[ "$CURRENT_SECTION" -ge 0 ]] \
      && section_requires_bullet "${SECTION_NAMES[$CURRENT_SECTION]}" \
      && [[ "${SECTION_BULLETS[$CURRENT_SECTION]}" -eq 0 ]]; then
      fail "${SECTION_NAMES[$CURRENT_SECTION]} must contain a bullet"
    fi

    SECTION_NAME="${BASH_REMATCH[1]}"
    case "$SECTION_NAME" in
      Highlights) SECTION_ORDER=1 ;;
      Improved) SECTION_ORDER=2 ;;
      Fixed) SECTION_ORDER=3 ;;
      Install\ or\ update) SECTION_ORDER=4 ;;
      After\ updating) SECTION_ORDER=5 ;;
      Known\ issues) SECTION_ORDER=6 ;;
      *) fail "unknown H2 on line $LINE_NUMBER: $SECTION_NAME" ;;
    esac
    [[ "$SECTION_ORDER" -gt "$PREVIOUS_ORDER" ]] \
      || fail "H2 headings are not in the allowed order"

    PREVIOUS_ORDER="$SECTION_ORDER"
    CURRENT_SECTION="${#SECTION_NAMES[@]}"
    SECTION_NAMES+=("$SECTION_NAME")
    SECTION_BULLETS+=(0)
    SECTION_STEPS+=(0)
    SECTION_EXACT_DMG+=(0)
    continue
  fi

  [[ "$CURRENT_SECTION" -ge 0 ]] || continue
  [[ "$line" =~ ^-[[:space:]] ]] && SECTION_BULLETS[$CURRENT_SECTION]=1
  if [[ "${SECTION_NAMES[$CURRENT_SECTION]}" == "Install or update" \
    && "$line" =~ ^[0-9]+\.[[:space:]] ]]; then
    SECTION_STEPS[$CURRENT_SECTION]=1
  fi
  if [[ "${SECTION_NAMES[$CURRENT_SECTION]}" == "Install or update" \
    && "$line" == *"Lyrinotch-$VERSION.dmg"* ]]; then
    SECTION_EXACT_DMG[$CURRENT_SECTION]=1
  fi
done < "$NOTES_PATH"

if [[ "$CURRENT_SECTION" -ge 0 ]] \
  && section_requires_bullet "${SECTION_NAMES[$CURRENT_SECTION]}" \
  && [[ "${SECTION_BULLETS[$CURRENT_SECTION]}" -eq 0 ]]; then
  fail "${SECTION_NAMES[$CURRENT_SECTION]} must contain a bullet"
fi

CHANGE_SECTION_COUNT=0
INSTALL_SECTION_COUNT=0
for index in "${!SECTION_NAMES[@]}"; do
  case "${SECTION_NAMES[$index]}" in
    Highlights|Improved|Fixed) CHANGE_SECTION_COUNT=$((CHANGE_SECTION_COUNT + 1)) ;;
    Install\ or\ update)
      INSTALL_SECTION_COUNT=$((INSTALL_SECTION_COUNT + 1))
      [[ "${SECTION_STEPS[$index]}" -eq 1 ]] \
        || fail "Install or update must contain a numbered step"
      [[ "${SECTION_EXACT_DMG[$index]}" -eq 1 ]] \
        || fail "Install or update must name Lyrinotch-$VERSION.dmg"
      ;;
  esac
done

[[ "$CHANGE_SECTION_COUNT" -gt 0 ]] \
  || fail "release notes need Highlights, Improved, or Fixed"
[[ "$INSTALL_SECTION_COUNT" -eq 1 ]] \
  || fail "release notes need exactly one Install or update section"

while IFS= read -r dmg_name; do
  [[ "$dmg_name" == "Lyrinotch-$VERSION.dmg" ]] \
    || fail "DMG name $dmg_name does not match version $VERSION"
done < <(grep -oE 'Lyrinotch-[0-9][0-9A-Za-z._-]*\.dmg' "$NOTES_PATH" || true)

echo "release notes OK: $VERSION ($BUILD)"
