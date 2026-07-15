#!/bin/bash
# Builds Marker.app into ./build. Run the app from there so macOS TCC
# (Accessibility permission) is granted to a stable, signed bundle.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Marker.app
# Overwriting the bundle under a running instance makes TCC silently drop
# its Accessibility grant (on-disk signature no longer matches the process).
if pgrep -xq Marker; then
  echo "Stopping running Marker (bundle is about to be replaced)…"
  pkill -x Marker || true
  sleep 0.5
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/Marker "$APP/Contents/MacOS/Marker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Embed Sparkle (SPM binary artifact) and point the executable at it.
SPARKLE_FW="$(find .build/artifacts -name Sparkle.framework -type d | head -1)"
[ -n "$SPARKLE_FW" ] || { echo "!! Sparkle.framework not found in .build/artifacts" >&2; exit 1; }
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Marker" 2>/dev/null || true

# Sign with a real identity: ad-hoc signatures change cdhash on every
# rebuild, which silently revokes the Accessibility (TCC) grant.
IDENTITY="${MARKER_SIGN_IDENTITY:-Developer ID Application}"
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "Built $APP"
echo "Run: open $APP"
