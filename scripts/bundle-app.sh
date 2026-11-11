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

# User manual ships in the bundle so Help → MotStar User Manual works offline.
if [ -f docs/USER-MANUAL.md ]; then
    cp docs/USER-MANUAL.md "$APP/Contents/Resources/UserManual.md"
fi

# App resources (AboutLogo, bundled web assets incl. mermaid.min.js)
if [ -d "Sources/MotStar/Resources" ]; then
    cp -R Sources/MotStar/Resources/. "$APP/Contents/Resources/"
fi

# Bundle version comes from AppInfo.swift (the single source of truth) so the
# Info.plist can never drift from the app's own constants.
VERSION=$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/MotStar/Models/AppInfo.swift | head -1)
BUILD=$(sed -n 's/.*static let build = "\([^"]*\)".*/\1/p' Sources/MotStar/Models/AppInfo.swift | head -1)
[ -n "$VERSION" ] || { echo "error: could not read version from AppInfo.swift" >&2; exit 1; }
[ -n "$BUILD" ] || BUILD=1
echo "==> Version $VERSION (build $BUILD)"

cat > "$APP/Contents/Info.plist" <<PLIST
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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Signing"
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [ -n "$SIGN_ID" ]; then
    codesign --force --deep --sign "$SIGN_ID" --options runtime --timestamp "$APP"
    echo "==> Signed with: $SIGN_ID"
else
    SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
    if [ -n "$SIGN_ID" ]; then
        codesign --force --deep --sign "$SIGN_ID" --options runtime --timestamp "$APP"
        echo "==> Signed with: $SIGN_ID (Apple Development — not distributable)"
    else
        codesign --force --deep --sign - "$APP"
        echo "==> Ad-hoc signed (no Apple Development identity found)"
    fi
fi

echo "==> Done: $APP"
