# Releasing Lyrinotch

This runbook produces a Developer ID-signed, notarized DMG and its SHA-256
checksum. The release script deliberately fails closed when the source version,
tag, release notes, packaged app, or signing identity disagree.

Do not publish an artifact created with `--local`. Local builds are intended only
for development and may be ad-hoc signed.

## Prerequisites

- macOS with Xcode command-line tools and Swift 5.10+
- A clean release commit on `master` (or the release branch)
- An Apple **Developer ID Application** certificate in the signing keychain
- The certificate's 10-character Team ID
- Notary service credentials saved in a keychain profile
- GitHub CLI authenticated with `gh auth login` (recommended)

The commands below use placeholders. They do not assume a certificate or notary
credential exists, and the repository scripts never contain those credentials.

The version source of truth is `Resources/Info.plist`:

- `CFBundleShortVersionString` is the public version, for example `1.0.1`.
- `CFBundleVersion` is a monotonically increasing integer build string, for
  example `1`.

Every release also requires `docs/release-notes-<version>.md`. Use this exact
structure (optional sections may be omitted, but retained headings stay in this
order and each retained change/status section contains at least one bullet):

```markdown
# Lyrinotch 1.0.1

> Build 1 · macOS 14+

One-sentence release summary.

## Highlights

- User-visible highlight.

## Improved

- User-visible improvement.

## Fixed

- User-visible fix.

## Install or update

1. Open **Lyrinotch-1.0.1.dmg**.
2. Drag **Lyrinotch** to **Applications** and replace the previous version.

## After updating

- Any required follow-up action.

## Known issues

- Any verified known issue.
```

At least one of **Highlights**, **Improved**, or **Fixed** is required, as is
**Install or update** with a numbered step naming the exact versioned DMG.
Do not use the placeholder markers rejected by the validator. State signing,
notarization, stapling, or verification status only after the corresponding
artifact checks below have actually passed.

## 1. Bump and validate release metadata

Edit `Resources/Info.plist` and create the matching release-notes file before
committing. Then run this preflight with the intended version:

```bash
set -euo pipefail

VERSION="1.0.1"
BUILD="1"
TAG="v${VERSION}"
NOTES="docs/release-notes-${VERSION}.md"

PLIST_VERSION="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
PLIST_BUILD="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' Resources/Info.plist)"

test "$VERSION" = "$PLIST_VERSION"
test "$BUILD" = "$PLIST_BUILD"
bash scripts/check-release-notes.sh
plutil -lint Resources/Info.plist
swift test
```

Commit the plist, release notes, and intended code changes. Confirm the release
commit has no tracked or untracked changes:

```bash
git status --short
```

The output must be empty.

## 2. Create a local annotated tag

Create the tag locally, but do not push it until the notarized artifact passes all
verification steps:

```bash
git tag -a "$TAG" -m "Lyrinotch ${VERSION}"
test "$(git rev-list -n 1 "$TAG")" = "$(git rev-parse HEAD)"
test "$(git cat-file -t "refs/tags/$TAG")" = "tag"
```

`scripts/create-dmg.sh` independently checks that:

- `$TAG` is exactly `v<CFBundleShortVersionString>`;
- it is an annotated tag pointing at `HEAD`;
- `CFBundleVersion` is an integer string;
- the release notes pass `scripts/check-release-notes.sh`; and
- the working tree is clean.

## 3. Configure signing and notary credentials

List available code-signing identities and select the exact Developer ID
Application identity:

```bash
security find-identity -v -p codesigning

export SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
export UPDATE_TEAM_ID="ABCDE12345"
export DMG_SIGN_IDENTITY="$SIGN_IDENTITY"
```

Create a notary keychain profile once, outside the repository. The command prompts
for the Apple ID, Team ID, and app-specific password instead of putting a password
in shell history:

```bash
xcrun notarytool store-credentials "lyrinotch-notary"
```

Set the profile name for this release session:

```bash
export NOTARY_PROFILE="lyrinotch-notary"
```

If the certificate or profile is unavailable, stop. Do not replace these release
steps with ad-hoc signing or `--local`.

## 4. Build and verify the app and DMG

Run the release-mode script from the tagged, clean commit:

```bash
./scripts/create-dmg.sh --tag "$TAG"
```

It performs all of the following before succeeding:

1. Builds `dist/Lyrinotch.app` with hardened runtime and timestamp signing.
2. Verifies the strict app signature, Developer ID authority, actual Team ID, and
   embedded `LyrinotchUpdateTeamIdentifier`.
3. Confirms the source plist and packaged plist versions and build numbers match.
4. Signs the DMG with `DMG_SIGN_IDENTITY`.
5. Runs `hdiutil verify`, mounts the image read-only, and checks the app and
   `/Applications` symlink.
6. Verifies the mounted app's strict signature and version.
7. Writes and immediately checks
   `dist/Lyrinotch-<version>.dmg.sha256`.

To create an unpublished development image instead:

```bash
./scripts/create-dmg.sh --local
```

`--skip-package` may reuse an existing app, but all applicable signature and
version checks still run.

## 5. Notarize, staple, and perform final verification

Submit the DMG and wait for Apple's result:

```bash
DMG="dist/Lyrinotch-${VERSION}.dmg"
CHECKSUM="${DMG}.sha256"

xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
```

Continue only when the notary result is `Accepted`. If it is rejected, use the
submission ID printed above with `xcrun notarytool log` and fix the artifact; do
not publish it.

Staple the accepted ticket and validate it:

```bash
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"
spctl --assess --type open \
  --context context:primary-signature \
  --verbose=4 "$DMG"
```

Stapling changes the DMG bytes, so the checksum created during packaging is no
longer final. Regenerate and verify it after stapling:

```bash
(
  cd dist
  shasum -a 256 "Lyrinotch-${VERSION}.dmg" \
    > "Lyrinotch-${VERSION}.dmg.sha256"
  shasum -a 256 -c "Lyrinotch-${VERSION}.dmg.sha256"
)
```

As a final manual smoke test, mount the DMG, verify that Gatekeeper accepts the
mounted app, launch it, and exercise **Check for Updates**:

```bash
open "$DMG"
# Replace the volume path below if Finder chose a suffix such as "Lyrinotch 1.0.1 1".
spctl --assess --type execute --verbose=4 \
  "/Volumes/Lyrinotch ${VERSION}/Lyrinotch.app"
codesign --verify --deep --strict --verbose=2 \
  "/Volumes/Lyrinotch ${VERSION}/Lyrinotch.app"
```

Eject the image after the smoke test.

## 6. Push the tag and publish both assets

Only after the notarized artifact and final checksum pass may the release notes
or Release describe that artifact as signed, notarized, stapled, or verified.
Then push and publish:

```bash
git push origin "$TAG"

gh release create "$TAG" \
  --verify-tag \
  --title "Lyrinotch ${VERSION}" \
  --notes-file "$NOTES" \
  "$DMG" "$CHECKSUM"
```

If the GitHub Release already exists, replace both assets together:

```bash
gh release upload "$TAG" "$DMG" "$CHECKSUM" --clobber
```

Do not upload a DMG without its matching post-staple checksum. Do not reuse a
checksum from before notarization.

## 7. Verify the published release and updater

Inspect the GitHub metadata and verify a freshly downloaded copy, not the local
build output:

```bash
gh release view "$TAG" --json tagName,isDraft,isPrerelease,assets

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lyrinotch-release-verify.XXXXXX")"
gh release download "$TAG" --dir "$VERIFY_DIR" \
  --pattern "Lyrinotch-${VERSION}.dmg" \
  --pattern "Lyrinotch-${VERSION}.dmg.sha256"
(
  cd "$VERIFY_DIR"
  shasum -a 256 -c "Lyrinotch-${VERSION}.dmg.sha256"
)
```

Then confirm:

- The Release is published (not a draft) and is the intended Latest release.
- `/releases/latest` and the GitHub API return `tag_name: v<version>`.
- An older Developer ID build offers the automatic update.
- The downloaded app is replaced, the new version opens, and user settings remain.
- An ad-hoc/local build offers only the manual release-page path.

The updater accepts only this repository's HTTPS GitHub Release asset. It checks
the optional GitHub digest, bundle identifier, version, strict code signature,
and configured Team ID. If replacement fails, the helper restores and reopens the
previous app when possible; if rollback itself fails, it keeps the hidden backup,
incoming candidate, and staging diagnostics instead of deleting recovery data.

## Release checklist

- [ ] Source plist version and integer build number were bumped.
- [ ] `bash scripts/check-release-notes.sh` accepts the complete release notes.
- [ ] Tests pass and the release commit is clean.
- [ ] Annotated `v<version>` tag points exactly at the release commit.
- [ ] App and DMG use Developer ID Application signing, not ad-hoc signing.
- [ ] Signature Team ID matches `LyrinotchUpdateTeamIdentifier`.
- [ ] Notary result is `Accepted`; ticket is stapled and validates.
- [ ] `hdiutil`, `codesign`, and Gatekeeper verification pass.
- [ ] Post-staple SHA-256 file verifies locally.
- [ ] Tag is pushed only after artifact verification.
- [ ] DMG and matching checksum are both attached to the Release.
- [ ] Freshly downloaded checksum and updater smoke tests pass.

## Troubleshooting

| Issue | Action |
|---|---|
| Release-note validator reports an error | Fix the reported filename, metadata line, summary, section order/content, DMG name, or placeholder marker, then rerun `bash scripts/check-release-notes.sh`. |
| Tag mismatch or tag does not point at HEAD | Stop and reconcile the plist, release commit, and local annotated tag before building. |
| Release app is ad-hoc signed | Set a valid `SIGN_IDENTITY` and `UPDATE_TEAM_ID`; do not use `--local`. |
| Team IDs do not match | Confirm both the certificate's TeamIdentifier and the plist's `LyrinotchUpdateTeamIdentifier`. |
| Notarization is rejected | Read `xcrun notarytool log <submission-id>`, fix the reported signing/bundle issue, and rebuild. |
| Stapler cannot find a ticket | Confirm the exact submitted DMG was accepted and was not rebuilt after submission. |
| Checksum fails after stapling | Regenerate the checksum from the final stapled DMG and upload both files again. |
| Automatic update rejects the DMG | Confirm asset origin, bundle ID/version, Developer ID signature, Team ID, and final GitHub digest. |
