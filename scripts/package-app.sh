#!/usr/bin/env bash
# Build a runnable Lyrinotch.app from the Swift package (release).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
UPDATE_TEAM_ID="${UPDATE_TEAM_ID:-}"
APP_NAME="Lyrinotch"
BUNDLE_ID="app.lyrinotch.Lyrinotch"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Building $APP_NAME ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Lyrinotch"
if [[ ! -x "$BIN" ]]; then
  echo "error: binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Localized macOS permission-prompt text belongs to the main app bundle.
for locale in en zh-Hant zh-Hans ja; do
  STRINGS_SOURCE="$ROOT/Resources/$locale.lproj/InfoPlist.strings"
  if [[ -f "$STRINGS_SOURCE" ]]; then
    mkdir -p "$RESOURCES_DIR/$locale.lproj"
    cp "$STRINGS_SOURCE" "$RESOURCES_DIR/$locale.lproj/InfoPlist.strings"
  fi
done

# SPM resource bundle + menu bar PNGs.
# Do NOT put loose items at the .app root (codesign: "unsealed contents").
# MenuBarIcon loader probes Contents/Resources and Contents/MacOS.
BIN_DIR="$(dirname "$BIN")"
RESOURCE_BUNDLE="$BIN_DIR/Lyrinotch_Lyrinotch.bundle"

install_resource_bundle() {
  local dest="$1"
  rm -rf "$dest"
  cp -R "$RESOURCE_BUNDLE" "$dest"
  if [[ ! -f "$dest/Info.plist" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.lyrinotch.Lyrinotch.resources" "$dest/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string Lyrinotch_Lyrinotch" "$dest/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string BNDL" "$dest/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$dest/Info.plist"
  fi
}

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  echo "==> Copying SPM resource bundle (Resources + MacOS)"
  install_resource_bundle "$RESOURCES_DIR/Lyrinotch_Lyrinotch.bundle"
  install_resource_bundle "$MACOS_DIR/Lyrinotch_Lyrinotch.bundle"
else
  echo "warning: SPM resource bundle not found at $RESOURCE_BUNDLE" >&2
fi

# Flat PNGs for NSImage(contentsOf:) fallbacks.
if [[ -d "$ROOT/Sources/Lyrinotch/Resources" ]]; then
  cp "$ROOT/Sources/Lyrinotch/Resources/"MenuBarIcon*.png "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Compile Assets.xcassets → Assets.car so MenuBarExtra(image:) / NSImage(named:) work.
ASSETS="$ROOT/Sources/Lyrinotch/Resources/Assets.xcassets"
if [[ -d "$ASSETS" ]]; then
  echo "==> Compiling Assets.xcassets → Assets.car"
  ACTOOL_OUT="$(mktemp -d)"
  xcrun actool \
    --compile "$ACTOOL_OUT" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$ACTOOL_OUT/partial.plist" \
    "$ASSETS" >/dev/null
  if [[ -f "$ACTOOL_OUT/Assets.car" ]]; then
    cp "$ACTOOL_OUT/Assets.car" "$RESOURCES_DIR/Assets.car"
    echo "    Assets.car ($(wc -c < "$RESOURCES_DIR/Assets.car" | tr -d ' ') bytes)"
  else
    echo "warning: actool did not produce Assets.car" >&2
  fi
  rm -rf "$ACTOOL_OUT"
fi

# App icon (Dock / Finder / About)
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"
fi
# PNG twin for Settings → 系統 about header (NSImage from file).
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
  cp "$ROOT/Resources/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
fi

ENTITLEMENTS="$ROOT/Resources/Lyrinotch.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements at $ENTITLEMENTS" >&2
  exit 1
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  if [[ -n "$UPDATE_TEAM_ID" ]]; then
    echo "warning: UPDATE_TEAM_ID is set but SIGN_IDENTITY is ad-hoc (-)." >&2
    echo "         Skipping LyrinotchUpdateTeamIdentifier so automatic install stays disabled." >&2
  fi
  echo "==> Ad-hoc codesign (automatic installation remains disabled)"
  codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR"
else
  if [[ -z "$UPDATE_TEAM_ID" ]]; then
    echo "error: UPDATE_TEAM_ID is required with SIGN_IDENTITY" >&2
    exit 1
  fi
  if [[ ! "$UPDATE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "error: UPDATE_TEAM_ID must be a 10-character Apple Developer Team ID" >&2
    exit 1
  fi
  # Only Developer ID builds embed the Team ID used by the verified updater.
  /usr/libexec/PlistBuddy -c "Add :LyrinotchUpdateTeamIdentifier string $UPDATE_TEAM_ID" "$CONTENTS/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :LyrinotchUpdateTeamIdentifier $UPDATE_TEAM_ID" "$CONTENTS/Info.plist"
  echo "==> Developer ID codesign (hardened runtime + audio-input entitlement)"
  # audio-input is required under Hardened Runtime for mic-based lyric offset calibration.
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

echo "==> Verifying"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | head -20
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  ACTUAL_TEAM_ID="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  if [[ "$ACTUAL_TEAM_ID" != "$UPDATE_TEAM_ID" ]]; then
    echo "error: signed TeamIdentifier '$ACTUAL_TEAM_ID' does not match UPDATE_TEAM_ID '$UPDATE_TEAM_ID'" >&2
    exit 1
  fi
fi
plutil -lint "$CONTENTS/Info.plist"

echo ""
echo "Done: $APP_DIR"
echo "Open with:  open \"$APP_DIR\""
echo "Install:    cp -R \"$APP_DIR\" /Applications/"
echo "Login item: enable from the menu bar after first launch of the .app"
echo "Automation: System Settings → Privacy & Security → Automation → allow Spotify + Music"
