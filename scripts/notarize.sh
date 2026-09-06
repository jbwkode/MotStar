#!/bin/bash
# Notarizes and staples a release artifact (DMG or ZIP) with Apple's notary
# service. Requires a Developer ID Application certificate on the signing
# identity used to build the app (see bundle-app.sh) and App Store Connect
# API credentials.
#
# Usage:
#   bash scripts/notarize.sh build/MotStar-0.3.7.dmg
#
# Credentials (or env):
#   -k/--key <path>       API key .p8 file   (env: ASC_API_KEY)
#   -i/--key-id <id>      API key ID         (env: ASC_KEY_ID)
#   -s/--issuer <uuid>    API issuer ID      (env: ASC_ISSUER)
#
# Example (defaults used in this project's release flow):
#   bash scripts/notarize.sh build/MotStar-0.3.7.dmg
#       --key ~/Downloads/AuthKey_Z37Z8S245M.p8 \
#       --key-id Z37Z8S245M \
#       --issuer 6c15956a-62a1-47f5-b602-8993447a1215
set -euo pipefail

FILE="${1:-}"
[ -n "$FILE" ] && [ -f "$FILE" ] || { echo "error: pass a .dmg or .zip to notarize" >&2; exit 1; }

KEY="${ASC_API_KEY:-}"
KEY_ID="${ASC_KEY_ID:-}"
ISSUER="${ASC_ISSUER:-}"

while [ $# -gt 1 ]; do
    case "$2" in
        -k|--key) KEY="$3"; shift 2 ;;
        -d|--key-id) KEY_ID="$3"; shift 2 ;;
        -i|--issuer) ISSUER="$3"; shift 2 ;;
        *) shift ;;
    esac
done

[ -n "$KEY" ] && [ -n "$KEY_ID" ] && [ -n "$ISSUER" ] || {
    echo "error: missing API credentials (use --key/--key-id/--issuer or ASC_API_KEY/ASC_KEY_ID/ASC_ISSUER)" >&2
    exit 1
}

AUTH=(--key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER")

echo "==> Submitting $(basename "$FILE") to Apple notary service"
xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait

echo "==> Stapling"
xcrun stapler staple "$FILE"

echo "==> Verifying"
if [ "${FILE##*.}" = "app" ]; then
    spctl --assess --type open --context context:primary-signature -v "$FILE"
else
    # Assess the app inside the container.
    MNT=$(mktemp -d)
    if [ "${FILE##*.}" = "zip" ]; then
        ditto -x -k "$FILE" "$MNT"
        APP=$(find "$MNT" -maxdepth 2 -name "*.app" | head -1)
    else
        hdiutil attach "$FILE" -nobrowse -readonly -quiet -mountpoint "$MNT"
        APP="$MNT/$(basename "$FILE" .dmg).app"
        [ -d "$APP" ] || APP=$(find "$MNT" -maxdepth 1 -name "*.app" | head -1)
    fi
    spctl --assess --type open --context context:primary-signature -v "$APP"
    xcrun stapler validate "$APP"
    if [ "${FILE##*.}" = "dmg" ]; then hdiutil detach "$MNT" -quiet; fi
    rm -rf "$MNT"
fi

echo "==> Done: $(basename "$FILE") is notarized and stapled"
