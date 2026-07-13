#!/usr/bin/env bash
# Build → sign (Developer ID, hardened runtime) → notarize → staple → DMG.
# Credentials: reuses the `waymark-notary` keychain profile
# (xcrun notarytool store-credentials — see wspaces/scripts/notarize.sh).
set -euo pipefail

cd "$(dirname "$0")/.."

KEYCHAIN_PROFILE="${NOTARY_PROFILE:-waymark-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP="build/Marker.app"
DIST="build/dist"
DMG="$DIST/marker-$VERSION.dmg"

./build-app.sh

echo "==> Verifying signature + hardened runtime…"
codesign --verify --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E "flags=.*runtime" \
  || { echo "!! Hardened runtime flag missing — notarization will reject." >&2; exit 1; }

echo "==> Notarizing (submit + wait)…"
rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/Marker.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Building DMG (app + Applications shortcut)…"
DMG_STAGE="$DIST/dmg"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "Marker" -srcfolder "$DMG_STAGE" -fs HFS+ -ov -format UDZO "$DMG"
xcrun stapler staple "$DMG" || true

echo
echo "✅ Done: $DMG"
echo "   Gatekeeper check: spctl -a -vvv -t install \"$APP\""
