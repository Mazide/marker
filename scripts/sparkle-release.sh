#!/usr/bin/env bash
# Generate the Sparkle appcast for Marker from the notarized DMG.
# Output: build/sparkle/ (versioned DMG + appcast.xml), download URLs under
# https://getwaymark.net/marker/. Signing uses the ed25519 key already in
# the keychain (same one waymark uses — same SUPublicEDKey).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)"
DMG="build/dist/marker-$VERSION.dmg"
OUT="build/sparkle"
GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"

[ -f "$DMG" ] || { echo "!! Missing $DMG — run scripts/notarize.sh first." >&2; exit 1; }
[ -x "$GENERATE_APPCAST" ] || { echo "!! Missing $GENERATE_APPCAST — run swift build first." >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DMG" "$OUT/marker-$VERSION-$BUILD.dmg"

"$GENERATE_APPCAST" \
  --download-url-prefix "https://getmarkerapp.net/" \
  --link "https://getmarkerapp.net/" \
  --maximum-versions 5 \
  "$OUT"

grep -q "sparkle:edSignature" "$OUT/appcast.xml" \
  || { echo "!! appcast has no edSignature — updates would be rejected." >&2; exit 1; }

echo "✅ Appcast ready: $OUT/appcast.xml"