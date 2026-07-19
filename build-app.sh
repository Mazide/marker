#!/bin/bash
# Builds Marker.app into ./build. Run the app from there so macOS TCC
# (Accessibility permission) is granted to a stable, signed bundle.
set -euo pipefail
cd "$(dirname "$0")"

# Const-value emission feeds appintentsmetadataprocessor below — without
# it App Intents are invisible to Shortcuts/Spotlight (SwiftPM has no
# built-in App Intents extraction; this replicates Xcode's build phase).
AIM_TMP="$(mktemp -d)"
trap 'rm -rf "$AIM_TMP"' EXIT
printf '["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","EntityQuery","TransientAppEntity","DynamicOptionsProvider","IntentValueQuery","AssistantIntent","AssistantEntity","AssistantEnum"]' \
  > "$AIM_TMP/protocols.json"
swift build -c release \
  -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
  -Xswiftc -Xfrontend -Xswiftc "$AIM_TMP/protocols.json" \
  -Xswiftc -emit-const-values

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
cp .build/release/marker-cli "$APP/Contents/MacOS/marker-cli"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# App Intents metadata (Shortcuts/Spotlight/Siri discovery).
find "$PWD/Sources/Marker" -name '*.swift' > "$AIM_TMP/srcs.txt"
echo "$PWD/.build/arm64-apple-macosx/release/Marker.build/Marker.swiftconstvalues" \
  > "$AIM_TMP/constvals.txt"
xcrun appintentsmetadataprocessor \
  --output "$APP/Contents/Resources" \
  --toolchain-dir /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
  --module-name Marker \
  --sdk-root "$(xcrun --show-sdk-path --sdk macosx)" \
  --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --source-file-list "$AIM_TMP/srcs.txt" \
  --swift-const-vals-list "$AIM_TMP/constvals.txt" \
  --binary-file "$PWD/.build/release/Marker" \
  --force --quiet-warnings
[ -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ] \
  || { echo "!! App Intents metadata missing — Shortcuts would not see Marker's actions." >&2; exit 1; }

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
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/MacOS/marker-cli"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "Built $APP"
echo "Run: open $APP"
