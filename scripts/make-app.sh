#!/bin/bash
# Builds release and assembles dist/UIScore.app (signed) plus dist/UIScore.zip.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ScreenCheck"
APP="dist/UIScore.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenCheck"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>UIScore</string>
<key>CFBundleDisplayName</key><string>UIScore</string>
<key>CFBundleIdentifier</key><string>com.screencheck.app</string>
<key>CFBundleExecutable</key><string>ScreenCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>UIScore reads your newest screenshot from the Desktop.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
# Stable local identity (see docs/DEVELOPMENT.md); ad-hoc when it is not set up on this machine.
DEV="$HOME/Library/Application Support/UIScoreDev"
KC="$DEV/signing.keychain-db"
if [ -f "$KC" ] && [ -f "$DEV/keychain-password" ] \
   && security unlock-keychain -p "$(cat "$DEV/keychain-password")" "$KC" \
   && security find-identity -v -p codesigning "$KC" | grep -q "UIScore Local Signing"; then
  codesign --force --deep --keychain "$KC" -s "UIScore Local Signing" "$APP"
else
  # Ad-hoc, but with a fixed designated requirement so every build keeps the same identity.
  codesign --force --deep -s - -r='designated => identifier "com.screencheck.app"' "$APP"
fi
(cd dist && ditto -c -k --keepParent "UIScore.app" UIScore.zip)
echo "Built $APP and dist/UIScore.zip"
