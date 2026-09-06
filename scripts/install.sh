#!/bin/bash
# MotStar installer — downloads the latest release DMG and installs to /Applications.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/jbwkode/MotStar/main/scripts/install.sh | bash
#
# Or with a pinned version:
#   VERSION=v0.3.2 bash <(curl -sL https://raw.githubusercontent.com/jbwkode/MotStar/main/scripts/install.sh)
#
# Env: REPO=jboss/name  VERSION=latest|vX.Y.Z
set -euo pipefail

REPO="${REPO:-jbwkode/MotStar}"
VERSION="${VERSION:-latest}"
APP_NAME="MotStar.app"

# --- GitHub auth -----------------------------------------------------------
# Public repos need no token. Private repos (like the current MotStar repo)
# require one: export GH_TOKEN="$(gh auth token)" or set GH_TOKEN yourself.
AUTH=()
if [ -n "${GH_TOKEN:-}" ]; then
    AUTH=(-H "Authorization: Bearer $GH_TOKEN")
elif command -v gh >/dev/null 2>&1 && GH_TOKEN_VALUE="$(gh auth token 2>/dev/null || true)" && [ -n "$GH_TOKEN_VALUE" ]; then
    AUTH=(-H "Authorization: Bearer $GH_TOKEN_VALUE")
    export GH_TOKEN="$GH_TOKEN_VALUE"
fi

# --- macOS version gate (MotStar needs macOS 14+) -------------------------
if ! command -v sw_vers >/dev/null 2>&1; then
    echo "error: this installer is for macOS only." >&2; exit 1
fi
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
    echo "error: MotStar requires macOS 14 (Sonoma) or later (you have $(sw_vers -productVersion))." >&2
    exit 1
fi

echo "==> MotStar installer — repo: $REPO, version: ${VERSION}"

# --- Resolve release asset URL -------------------------------------------
if [ "$VERSION" = "latest" ]; then
    API_URL="https://api.github.com/repos/${REPO}/releases/latest"
else
    API_URL="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
fi

JSON=$(curl -fsSL "${AUTH[@]}" -H "Accept: application/vnd.github+json" "$API_URL" 2>/dev/null \
       || { echo "error: could not fetch release info from $API_URL (repo may be private — set GH_TOKEN or export GH_TOKEN=\"\$(gh auth token)\")." >&2; exit 1; })

DMG_URL=""
if command -v python3 >/dev/null 2>&1; then
    DMG_URL=$(printf '%s' "$JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    assets = data.get("assets", [])
    for a in assets:
        if a.get("name", "").endswith(".dmg"):
            print(a["browser_download_url"]); break
except Exception:
    pass')
fi
if [ -z "$DMG_URL" ]; then
    DMG_URL=$(printf '%s' "$JSON" | tr -d '\n' \
      | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1)
fi
if [ -z "$DMG_URL" ]; then
    echo "error: no .dmg asset found on the ${VERSION} release." >&2; exit 1
fi

echo "==> Downloading $DMG_URL"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
DMG="$TMP/MotStar.dmg"
curl -fSL "${AUTH[@]}" --progress-bar "$DMG_URL" -o "$DMG"

echo "==> Mounting disk image"
mkdir -p "$TMP/mnt"
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$TMP/mnt"

SRC_APP="$TMP/mnt/$APP_NAME"
if [ ! -d "$SRC_APP" ]; then
    echo "error: $APP_NAME not found inside the disk image." >&2
    hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true
    exit 1
fi

# --- Install into /Applications ------------------------------------------
DEST="/Applications/$APP_NAME"
if [ -d "$DEST" ]; then
    BACKUP="/Applications/${APP_NAME}.old-$(date +%Y%m%d-%H%M%S)"
    echo "==> Existing app found — moving it aside to $BACKUP"
    mv "$DEST" "$BACKUP"
fi

echo "==> Installing to $DEST"
ditto "$SRC_APP" "$DEST"
hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true

# Signed with an Apple Development identity (not yet notarized), so clear the
# quarantine flag — otherwise Gatekeeper blocks first launch on downloaded apps.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching MotStar"
open "$DEST"
echo "==> Done. MotStar installed at $DEST"
