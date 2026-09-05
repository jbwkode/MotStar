#!/bin/bash
# Generates build/AppIcon.icns from a square-ish source image.
# Usage: scripts/make-icon.sh [source]   (default: Resources/appicon-source.jpg)
# The source is center-cropped to a square, then resized to every .icns size.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-Resources/appicon-source.jpg}"
FULL="build/appicon-full.png"
TMP="build/appicon-square.png"
ICONSET="build/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
    echo "error: source image not found: $SRC" >&2
    exit 1
fi

W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
SIDE=$((W < H ? W : H))

echo "==> Source ${W}x${H}; converting to PNG"
sips -s format png "$SRC" --out "$FULL" >/dev/null
echo "==> Centre-cropping to ${SIDE}x${SIDE} square"
sips -c "$SIDE" "$SIDE" "$FULL" --out "$TMP" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

declare -a SIZES=(
  "16 icon_16x16"
  "32 icon_16x16@2x"
  "32 icon_32x32"
  "64 icon_32x32@2x"
  "128 icon_128x128"
  "256 icon_128x128@2x"
  "256 icon_256x256"
  "512 icon_256x256@2x"
  "512 icon_512x512"
  "1024 icon_512x512@2x"
)
for entry in "${SIZES[@]}"; do
    px=${entry%% *}
    name=${entry##* }
    sips -z "$px" "$px" "$TMP" --out "$ICONSET/$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o build/AppIcon.icns
echo "==> Done: build/AppIcon.icns"
