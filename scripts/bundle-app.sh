#!/bin/bash
# Bundles the MotStar release binary into build/MotStar.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building release binary"
swift build -c release --product MotStar

APP="build/MotStar.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MotStar "$APP/Contents/MacOS/MotStar"

# App icon (generated from Resources/appicon-source.* when present)
if ls Resources/appicon-source.* >/dev/null 2>&1; then
    SOURCE_ICON=$(ls Resources/appicon-source.* | head -1)
    echo "==> Building app icon from $SOURCE_ICON"
    HAS_ALPHA=$(sips -g hasAlpha "$SOURCE_ICON" 2>/dev/null | awk '{print $2}')
    if [ "$HAS_ALPHA" = "yes" ]; then
        # Transparent artwork (e.g. floating logos): pad to a square canvas.
        swift scripts/icon-prepare.swift "$SOURCE_ICON" build/appicon-prepared.png >/dev/null
        echo "    (transparent source — padded to square)"
    else
        # Opaque artwork (full-bleed tiles): copy as-is; make-icon crops square.
        cp "$SOURCE_ICON" build/appicon-prepared.png
    fi
    ./scripts/make-icon.sh build/appicon-prepared.png >/dev/null
    cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# App resources (AboutLogo, bundled web assets incl. mermaid.min.js)
if [ -d "Sources/MotStar/Resources" ]; then
    cp -R Sources/MotStar/Resources/. "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MotStar</string>
    <key>CFBundleIdentifier</key>
    <string>com.motstar.mac</string>
    <key>CFBundleName</key>
    <string>MotStar</string>
    <key>CFBundleDisplayName</key>
    <string>MotStar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.5</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "==> Signing"
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -n "$SIGN_ID" ]; then
    codesign --force --deep --sign "$SIGN_ID" "$APP"
    echo "==> Signed with: $SIGN_ID"
else
    codesign --force --deep --sign - "$APP"
    echo "==> Ad-hoc signed (no Apple Development identity found)"
fi

echo "==> Done: $APP"
