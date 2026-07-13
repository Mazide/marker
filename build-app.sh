#!/bin/bash
# Builds Marker.app into ./build. Run the app from there so macOS TCC
# (Accessibility permission) is granted to a stable, signed bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Marker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Marker "$APP/Contents/MacOS/Marker"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sign with a real identity: ad-hoc signatures change cdhash on every
# rebuild, which silently revokes the Accessibility (TCC) grant.
IDENTITY="${MARKER_SIGN_IDENTITY:-Developer ID Application}"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "Built $APP"
echo "Run: open $APP"
