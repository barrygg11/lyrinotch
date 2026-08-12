#!/usr/bin/env bash
# Build, validate, and wrap Lyrinotch.app in a drag-to-Applications DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${OUT_DIR:-$ROOT/dist}"
APP_NAME="Lyrinotch"
APP_DIR="$OUT_DIR/$APP_NAME.app"
SOURCE_PLIST="$ROOT/Resources/Info.plist"
SKIP_PACKAGE=0
LOCAL_BUILD=0
RELEASE_TAG=""
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
MOUNT_POINT=""

usage() {
  cat <<'EOF'
Usage: ./scripts/create-dmg.sh [options]

Options:
  --skip-package       Reuse an existing dist/Lyrinotch.app
  --tag vX.Y.Z         Require this annotated tag to match Info.plist and HEAD
  --local              Build an explicitly non-release DMG (tag, notes, and
                       Developer ID checks are skipped)
  -h, --help           Show this help

Release output:
  dist/Lyrinotch-<version>.dmg
  dist/Lyrinotch-<version>.dmg.sha256

Release mode is the default. It requires a clean tagged commit, matching release
notes, a Developer ID-signed app, and DMG_SIGN_IDENTITY (or SIGN_IDENTITY).
It verifies the app, image, mounted contents, and generated SHA-256 checksum.
Notarization and stapling remain explicit release steps in docs/releasing.md.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-package)
      SKIP_PACKAGE=1
      shift
      ;;
    --tag)
      [[ $# -ge 2 ]] || fail "--tag requires a value"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --local)
      LOCAL_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_command codesign
require_command hdiutil
require_command plutil
require_command shasum
[[ -x /usr/libexec/PlistBuddy ]] || fail "required command not found: /usr/libexec/PlistBuddy"
[[ -f "$SOURCE_PLIST" ]] || fail "missing $SOURCE_PLIST"
plutil -lint "$SOURCE_PLIST" >/dev/null

SOURCE_VERSION="$(plist_value CFBundleShortVersionString "$SOURCE_PLIST" || true)"
SOURCE_BUILD="$(plist_value CFBundleVersion "$SOURCE_PLIST" || true)"
[[ -n "$SOURCE_VERSION" ]] || fail "CFBundleShortVersionString is empty"
[[ "$SOURCE_BUILD" =~ ^[0-9]+$ ]] || fail "CFBundleVersion must be an integer string"
EXPECTED_TAG="v${SOURCE_VERSION}"
RELEASE_NOTES="$ROOT/docs/release-notes-${SOURCE_VERSION}.md"

if [[ "$LOCAL_BUILD" -eq 0 ]]; then
  [[ -z "$RELEASE_TAG" ]] && RELEASE_TAG="$EXPECTED_TAG"
  [[ "$RELEASE_TAG" == "$EXPECTED_TAG" ]] \
    || fail "tag '$RELEASE_TAG' does not match Info.plist version '$SOURCE_VERSION'"
  bash "$ROOT/scripts/check-release-notes.sh"
  [[ -z "$(git status --porcelain --untracked-files=normal)" ]] \
    || fail "release builds require a clean working tree"
  git show-ref --verify --quiet "refs/tags/$RELEASE_TAG" \
    || fail "annotated tag '$RELEASE_TAG' does not exist"
  [[ "$(git cat-file -t "refs/tags/$RELEASE_TAG")" == "tag" ]] \
    || fail "release tag '$RELEASE_TAG' must be annotated"
  [[ "$(git rev-list -n 1 "$RELEASE_TAG")" == "$(git rev-parse HEAD)" ]] \
    || fail "release tag '$RELEASE_TAG' does not point at HEAD"

  if [[ -z "$DMG_SIGN_IDENTITY" && -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
    DMG_SIGN_IDENTITY="$SIGN_IDENTITY"
  fi
  [[ -n "$DMG_SIGN_IDENTITY" ]] \
    || fail "release mode requires DMG_SIGN_IDENTITY (or SIGN_IDENTITY)"
else
  [[ -z "$RELEASE_TAG" ]] || fail "--tag and --local cannot be used together"
  echo "warning: --local skips release tag, notes, and Developer ID enforcement" >&2
fi

mkdir -p "$OUT_DIR"
if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
  echo "==> Packaging .app first"
  "$ROOT/scripts/package-app.sh"
elif [[ ! -d "$APP_DIR" ]]; then
  fail "--skip-package requested but $APP_DIR is missing"
fi

[[ -d "$APP_DIR" ]] || fail "missing $APP_DIR"
APP_PLIST="$APP_DIR/Contents/Info.plist"
[[ -f "$APP_PLIST" ]] || fail "missing $APP_PLIST"
plutil -lint "$APP_PLIST" >/dev/null

APP_VERSION="$(plist_value CFBundleShortVersionString "$APP_PLIST" || true)"
APP_BUILD="$(plist_value CFBundleVersion "$APP_PLIST" || true)"
[[ "$APP_VERSION" == "$SOURCE_VERSION" ]] \
  || fail "packaged app version '$APP_VERSION' does not match source '$SOURCE_VERSION'"
[[ "$APP_BUILD" == "$SOURCE_BUILD" ]] \
  || fail "packaged app build '$APP_BUILD' does not match source '$SOURCE_BUILD'"

echo "==> Verifying packaged app signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
if [[ "$LOCAL_BUILD" -eq 0 ]]; then
  grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_DETAILS" \
    || fail "release app is not signed with Developer ID Application"
  grep -Eq '^CodeDirectory .*\(runtime\)' <<<"$SIGNATURE_DETAILS" \
    || fail "release app signature does not enable hardened runtime"
  grep -q '^Timestamp=' <<<"$SIGNATURE_DETAILS" \
    || fail "release app signature does not contain a trusted timestamp"
  ACTUAL_TEAM_ID="$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$SIGNATURE_DETAILS")"
  EMBEDDED_TEAM_ID="$(plist_value LyrinotchUpdateTeamIdentifier "$APP_PLIST" || true)"
  [[ -n "$ACTUAL_TEAM_ID" && "$ACTUAL_TEAM_ID" == "$EMBEDDED_TEAM_ID" ]] \
    || fail "signature Team ID and LyrinotchUpdateTeamIdentifier do not match"
fi

DMG_NAME="${APP_NAME}-${SOURCE_VERSION}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
CHECKSUM_NAME="${DMG_NAME}.sha256"
CHECKSUM_PATH="$OUT_DIR/$CHECKSUM_NAME"
VOL_NAME="${APP_NAME} ${SOURCE_VERSION}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lyrinotch-dmg.XXXXXX")"

cleanup() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

echo "==> Staging DMG contents"
cp -R "$APP_DIR" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"

echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
  echo "==> Signing DMG with Developer ID"
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
  if [[ "$LOCAL_BUILD" -eq 0 ]]; then
    DMG_SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"
    grep -q '^Authority=Developer ID Application:' <<<"$DMG_SIGNATURE_DETAILS" \
      || fail "release DMG is not signed with Developer ID Application"
    DMG_TEAM_ID="$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$DMG_SIGNATURE_DETAILS")"
    [[ "$DMG_TEAM_ID" == "$ACTUAL_TEAM_ID" ]] \
      || fail "DMG Team ID does not match the packaged app Team ID"
  fi
fi

echo "==> Verifying disk image integrity"
hdiutil verify "$DMG_PATH"

echo "==> Mounting read-only to verify packaged contents"
ATTACH_OUTPUT="$(hdiutil attach -readonly -nobrowse "$DMG_PATH")"
MOUNT_POINT="$(awk -F '\t' '$NF ~ /^\/Volumes\// { mount = $NF } END { print mount }' <<<"$ATTACH_OUTPUT")"
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT/$APP_NAME.app" ]] \
  || fail "mounted DMG does not contain $APP_NAME.app"
[[ -L "$MOUNT_POINT/Applications" ]] \
  || fail "mounted DMG does not contain the Applications symlink"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] \
  || fail "Applications symlink has an unexpected target"

MOUNTED_PLIST="$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist"
[[ "$(plist_value CFBundleShortVersionString "$MOUNTED_PLIST")" == "$SOURCE_VERSION" ]] \
  || fail "mounted app version does not match $SOURCE_VERSION"
[[ "$(plist_value CFBundleVersion "$MOUNTED_PLIST")" == "$SOURCE_BUILD" ]] \
  || fail "mounted app build does not match $SOURCE_BUILD"
codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/$APP_NAME.app"
hdiutil detach "$MOUNT_POINT"
MOUNT_POINT=""

echo "==> Writing and checking SHA-256 checksum"
(
  cd "$OUT_DIR"
  shasum -a 256 "$DMG_NAME" > "$CHECKSUM_NAME"
  shasum -a 256 -c "$CHECKSUM_NAME"
)

SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "Done: $DMG_PATH ($SIZE)"
echo "SHA-256: $CHECKSUM_PATH"
if [[ "$LOCAL_BUILD" -eq 0 ]]; then
  echo "Validated release tag: $RELEASE_TAG"
  echo "Next: notarize and staple the DMG, then regenerate its checksum."
  echo "See:  docs/releasing.md"
else
  echo "Local artifact only; do not publish this DMG as a release."
fi
