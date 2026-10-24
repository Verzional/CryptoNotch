#!/bin/zsh
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

echo "🔨 Building CryptoNotch (Release)..."
xcodebuild -scheme CryptoNotch -configuration Release -derivedDataPath build build > /dev/null 2>&1
rm -rf CryptoNotch.app
cp -R build/Build/Products/Release/CryptoNotch.app ./

# Detect Developer ID Application signing identity, fallback to ad-hoc (-)
SIGN_ID=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | awk -F '"' '{print $2}')

if [ -n "$SIGN_ID" ]; then
    echo "🔏 Signing with Developer ID: $SIGN_ID"
    TIMESTAMP_ARGS=("--timestamp=none")
    if [ -n "$NOTARY_PROFILE" ] || [ "$1" = "--timestamp" ]; then
        TIMESTAMP_ARGS=("--timestamp")
    fi
    SPARKLE_DIR="CryptoNotch.app/Contents/Frameworks/Sparkle.framework/Versions/B"
    if [ -d "$SPARKLE_DIR" ]; then
        echo "   Signing Sparkle framework components..."
        codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" "$SPARKLE_DIR/XPCServices/Downloader.xpc"
        codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" "$SPARKLE_DIR/XPCServices/Installer.xpc"
        codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" "$SPARKLE_DIR/Updater.app"
        codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" "$SPARKLE_DIR/Autoupdate"
        codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" "CryptoNotch.app/Contents/Frameworks/Sparkle.framework"
    fi
    echo "   Signing CryptoNotch.app..."
    codesign -s "$SIGN_ID" --force --options runtime "${TIMESTAMP_ARGS[@]}" CryptoNotch.app
else
    echo "⚠️  Developer ID not found. Signing ad-hoc..."
    codesign -s - --force --deep CryptoNotch.app
fi

echo "📦 Packaging CryptoNotch.dmg..."
DMG_ROOT="build/dmg_root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R CryptoNotch.app "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f CryptoNotch.dmg
hdiutil create -volname "CryptoNotch" -srcfolder "$DMG_ROOT" -ov -format UDZO CryptoNotch.dmg > /dev/null 2>&1
rm -rf "$DMG_ROOT"

if [ -n "$SIGN_ID" ]; then
    echo "🔏 Signing CryptoNotch.dmg..."
    codesign -s "$SIGN_ID" --force "${TIMESTAMP_ARGS[@]}" CryptoNotch.dmg
fi

# Optional Notarization step if NOTARY_PROFILE is configured
if [ -n "$NOTARY_PROFILE" ]; then
    echo "🚀 Submitting to Apple Notary Service ($NOTARY_PROFILE)..."
    xcrun notarytool submit CryptoNotch.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple CryptoNotch.dmg
fi

echo "✅ DMG generated: CryptoNotch.dmg ($(du -h CryptoNotch.dmg | awk '{print $1}'))"
