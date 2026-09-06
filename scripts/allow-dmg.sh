#!/bin/bash
# MotStar DMG helper — prepares a downloaded DMG for MANUAL installation.
#
# When you download a DMG, macOS tags it (and everything inside) with the
# "quarantine" attribute. Gatekeeper then blocks the app on first launch
# because MotStar is not yet notarized. This script clears those attributes
# and opens the DMG so you can drag MotStar.app into /Applications normally.
#
# Usage:
#   bash allow-dmg.sh                          # uses the newest MotStar DMG in ~/Downloads
#   bash allow-dmg.sh /path/to/MotStar-0.3.4.dmg
set -euo pipefail

DMG="${1:-}"
if [ -z "$DMG" ]; then
    DMG=$(ls -t "$HOME"/Downloads/MotStar*.dmg 2>/dev/null | head -1 || true)
fi
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
    echo "error: no MotStar DMG found. Pass a path, e.g." >&2
    echo "  bash allow-dmg.sh ~/Downloads/MotStar-0.3.4.dmg" >&2
    exit 1
fi
DMG="$(cd "$(dirname "$DMG")" && pwd)/$(basename "$DMG")"
echo "==> DMG: $DMG"

echo "==> Clearing quarantine on the DMG itself"
xattr -dr com.apple.quarantine "$DMG" 2>/dev/null || true

echo "==> Mounting (read-only)"
MNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -quiet -mountpoint "$MNT"

APP="$MNT/MotStar.app"
if [ ! -d "$APP" ]; then
    echo "error: MotStar.app not found inside the DMG." >&2
    hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
    rmdir "$MNT" 2>/dev/null || true
    exit 1
fi

echo "==> Clearing quarantine on MotStar.app inside the DMG"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Opening in Finder — drag MotStar.app into Applications"
open "$MNT"

cat <<'EOF'

Done. When you drag MotStar.app into your Applications folder it will launch
normally (no right-click → Open needed).

If you prefer a fully automated install instead, run:
    bash install.sh
EOF
