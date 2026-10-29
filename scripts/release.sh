#!/bin/bash
# MotStar release pipeline: build → sign (Developer ID) → DMG + ZIP →
# notarize → staple → verify → optionally publish a GitHub release.
#
# Usage:
#   ./scripts/release.sh                      # build + notarize (no publish)
#   ./scripts/release.sh --publish            # …and create/update the release
#   ./scripts/release.sh --skip-notarize      # local build only (no Apple round-trip)
#
# Options:
#   --publish           Publish a GitHub release for the current version
#                       (published immediately, marked Latest)
#   --skip-notarize     Skip submission/staple/verify (dev/local artifacts)
#   --profile <name>    notarytool keychain profile (default: motstar)
#   --notes <file>      Release notes markdown (default: --generate-notes)
#
# Requirements:
#   - "Developer ID Application" certificate in the keychain
#   - notarytool credentials: `xcrun notarytool store-credentials <profile> ...`
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=0
SKIP_NOTARIZE=0
PROFILE="motstar"
NOTES=""
REPO_SLUG="jbwkode/MotStar"

while [ $# -gt 0 ]; do
    case "$1" in
        --publish) PUBLISH=1; shift ;;
        --skip-notarize) SKIP_NOTARIZE=1; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --notes) NOTES="$2"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "error: unknown option $1" >&2; exit 1 ;;
    esac
done

# --- Version (single source: AppInfo.swift) ---------------------------------
VERSION=$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/MotStar/Models/AppInfo.swift | head -1)
BUILD=$(sed -n 's/.*static let build = "\([^"]*\)".*/\1/p' Sources/MotStar/Models/AppInfo.swift | head -1)
[ -n "$VERSION" ] || { echo "error: could not read version from AppInfo.swift" >&2; exit 1; }
echo "==> MotStar $VERSION (build $BUILD)"

APP="build/MotStar.app"
DMG="build/MotStar-$VERSION.dmg"
ZIP="build/MotStar-v$VERSION-macOS.zip"

# --- Preconditions ----------------------------------------------------------
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [ -z "$SIGN_ID" ]; then
    echo "error: no 'Developer ID Application' certificate found in the keychain." >&2
    echo "       Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
    exit 1
fi
echo "==> Signing identity: $SIGN_ID"

if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        echo "error: notarytool keychain profile '$PROFILE' not found." >&2
        echo "       xcrun notarytool store-credentials $PROFILE --key <key.p8> --key-id <id> --issuer <uuid>" >&2
        exit 1
    fi
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "==> warning: working tree has uncommitted changes (continuing)"
fi

# --- Build + sign -----------------------------------------------------------
./scripts/bundle-app.sh
SIGN_INFO=$(codesign -dvv "$APP" 2>&1 || true)
if ! grep -q "Authority=Developer ID Application" <<<"$SIGN_INFO"; then
    echo "error: $APP is not signed with a Developer ID certificate — refusing to release." >&2
    exit 1
fi

# --- Artifacts --------------------------------------------------------------
# The DMG and ZIP are built after notarization (signed below) so both carry the
# stapled app. When notarization is skipped, build them straight away.
build_artifacts() {
    echo "==> Creating $DMG"
    rm -rf build/dmg-staging
    mkdir -p build/dmg-staging
    cp -R "$APP" build/dmg-staging/
    ln -s /Applications build/dmg-staging/Applications
    hdiutil create -volname MotStar -srcfolder build/dmg-staging -ov -format UDZO "$DMG" >/dev/null

    echo "==> Creating $ZIP"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
}

# --- Notarize, staple, rebuild from the stapled app, verify -----------------
if [ "$SKIP_NOTARIZE" -eq 0 ]; then
    # Pass 1: the app bundle itself. Stapling the app before packaging means
    # the ticket travels inside the DMG and the ZIP, so both work offline.
    echo "==> Submitting app bundle for notarization"
    APPZIP="build/MotStar-app-notarize.zip"
    rm -f "$APPZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$APPZIP"
    SUBMIT_LOG=$(xcrun notarytool submit "$APPZIP" --keychain-profile "$PROFILE" --wait 2>&1)
    echo "$SUBMIT_LOG" | tail -3
    rm -f "$APPZIP"
    if ! grep -q "status: Accepted" <<<"$SUBMIT_LOG"; then
        echo "error: app notarization did not succeed — not publishing." >&2
        grep -m1 -E "id:" <<<"$SUBMIT_LOG" >&2 || true
        exit 1
    fi
    echo "==> Stapling app"
    xcrun stapler staple "$APP" >/dev/null

    # Build both artifacts from the stapled app.
    build_artifacts

    # Pass 2: the DMG container. A DMG rebuilt after stapling has a new hash
    # and no ticket ("Record not found"), so it must be notarized in its final
    # form to be stapleable. ~1 minute extra, and the DMG then validates
    # offline like the app inside it.
    echo "==> Submitting $(basename "$DMG") for notarization"
    SUBMIT_LOG=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)
    echo "$SUBMIT_LOG" | tail -3
    if ! grep -q "status: Accepted" <<<"$SUBMIT_LOG"; then
        echo "error: DMG notarization did not succeed — not publishing." >&2
        grep -m1 -E "id:" <<<"$SUBMIT_LOG" >&2 || true
        exit 1
    fi

    echo "==> Stapling DMG"
    xcrun stapler staple "$DMG" >/dev/null

    echo "==> Verifying Gatekeeper acceptance"
    xcrun stapler validate "$DMG" >/dev/null
    echo "    DMG container: stapled ✓"

    MNT=$(mktemp -d)
    hdiutil attach "$DMG" -nobrowse -readonly -quiet -mountpoint "$MNT"
    spctl --assess --type open --context context:primary-signature -v "$MNT/MotStar.app" 2>&1 | tail -1
    xcrun stapler validate "$MNT/MotStar.app" >/dev/null
    hdiutil detach "$MNT" -quiet
    rm -rf "$MNT"

    UNZ=$(mktemp -d)
    ditto -x -k "$ZIP" "$UNZ"
    spctl --assess --type open --context context:primary-signature -v "$UNZ/MotStar.app" 2>&1 | tail -1
    xcrun stapler validate "$UNZ/MotStar.app" >/dev/null
    rm -rf "$UNZ"
    echo "==> Notarized and stapled ✓"
else
    echo "==> Skipping notarization (local build)"
    build_artifacts
fi

# --- Publish -----------------------------------------------------------------
if [ "$PUBLISH" -eq 1 ]; then
    if [ "$SKIP_NOTARIZE" -eq 1 ]; then
        echo "error: --publish requires notarization." >&2
        exit 1
    fi
    TAG="v$VERSION"
    echo "==> Publishing $TAG"
    cp scripts/install.sh /tmp/install-motstar.sh

    NOTES_ARGS=(--generate-notes)
    [ -n "$NOTES" ] && NOTES_ARGS=(--notes-file "$NOTES")

    if gh release view "$TAG" -R "$REPO_SLUG" >/dev/null 2>&1; then
        gh release upload "$TAG" "$DMG" "$ZIP" scripts/allow-dmg.sh /tmp/install-motstar.sh -R "$REPO_SLUG" --clobber
        gh release edit "$TAG" -R "$REPO_SLUG" --draft=false --latest "${NOTES_ARGS[@]}"
    else
        gh release create "$TAG" -R "$REPO_SLUG" --title "MotStar $VERSION" --latest "${NOTES_ARGS[@]}"
        gh release upload "$TAG" "$DMG" "$ZIP" scripts/allow-dmg.sh /tmp/install-motstar.sh -R "$REPO_SLUG" --clobber
    fi
    RELEASE_URL=$(gh release view "$TAG" -R "$REPO_SLUG" --json url --jq .url 2>/dev/null || echo "")
    echo "==> Release ready: ${RELEASE_URL:-$TAG}"
fi

echo
echo "==> Done: MotStar $VERSION"
echo "    $DMG"
echo "    $ZIP"
[ "$PUBLISH" -eq 1 ] && echo "    https://github.com/$REPO_SLUG/releases/tag/v$VERSION"
exit 0
