#!/usr/bin/env bash
# Build an arm64, ad-hoc-signed DMG for short-lived CI testing only.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -L build ]]; then
  echo "!! Refusing to use symlinked build directory." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "!! TEST DMG packaging requires an arm64 macOS runner." >&2
  exit 1
fi

for required_command in git codesign hdiutil shasum; do
  command -v "$required_command" >/dev/null 2>&1 \
    || { echo "!! Required command not found: $required_command" >&2; exit 1; }
done

SOURCE_SHA="$(git rev-parse HEAD)"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40,64}$ ]]; then
  echo "!! Could not determine a valid checked-out source commit." >&2
  exit 1
fi
SHORT_SHA="${SOURCE_SHA:0:12}"

APP="build/Marker.app"
DIST="build/test-dist"
STAGE="build/test-dmg-staging"
DMG_NAME="Marker-arm64-TEST-unnotarized-${SHORT_SHA}.dmg"
DMG="$DIST/$DMG_NAME"

# These paths are dedicated generated outputs; do not broaden cleanup scope.
rm -rf -- "$STAGE" "$DIST"
mkdir -p "$DIST" "$STAGE"
PACKAGE_COMPLETE=0
cleanup() {
  status=$?
  trap - EXIT
  rm -rf -- "$STAGE"
  if (( PACKAGE_COMPLETE == 0 )); then
    rm -f -- "$DMG" "$DMG.sha256"
  fi
  exit "$status"
}
trap cleanup EXIT

./build-app.sh --test-ad-hoc-sign

required_bundle_paths=(
  "$APP/Contents/MacOS/Marker"
  "$APP/Contents/MacOS/marker-cli"
  "$APP/Contents/Info.plist"
  "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
)
for required_path in "${required_bundle_paths[@]}"; do
  [[ -f "$required_path" ]] \
    || { echo "!! Required app bundle file missing: $required_path" >&2; exit 1; }
done
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] \
  || { echo "!! Required app framework missing: $APP/Contents/Frameworks/Sparkle.framework" >&2; exit 1; }

echo "==> Verifying ad-hoc app signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
if ! SIGNATURE_DETAILS="$(codesign --display --verbose=4 "$APP" 2>&1)"; then
  echo "!! Could not inspect the app signature." >&2
  exit 1
fi
case "$SIGNATURE_DETAILS" in
  *"Signature=adhoc"*)
    ;;
  *)
    echo "!! Expected an ad-hoc app signature; refusing to create a TEST DMG." >&2
    exit 1
    ;;
esac

cp -R "$APP" "$STAGE/Marker.app"
ln -s /Applications "$STAGE/Applications"

printf '%s\n' \
  'Marker arm64 TEST build — ad-hoc signed and NOT notarized.' \
  '' \
  'This is not an isolated profile. It keeps Marker’s normal bundle identity and uses normal history and settings.' \
  'If Marker offers to move itself to Applications, accepting can replace an installed copy of Marker.' \
  'Gatekeeper may reject this test build, and TCC permissions may not carry over after replacement.' \
  'Follow your organization’s security policy; ask its administrator if testing is blocked.' \
  > "$STAGE/TEST-BUILD-WARNING.txt"

printf '%s\n' \
  'Marker arm64 TEST/unnotarized DMG' \
  "Source commit: $SOURCE_SHA" \
  'Bundle identifier: dev.looseconfetti.marker (unchanged)' \
  'Signing: ad-hoc' \
  'Notarized: no' \
  > "$STAGE/PROVENANCE.txt"

echo "==> Creating $DMG_NAME..."
hdiutil create \
  -volname "Marker TEST $SHORT_SHA" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -ov \
  -format UDZO \
  "$DMG"

echo "==> Verifying DMG integrity..."
hdiutil verify "$DMG"
(
  cd "$DIST"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
PACKAGE_COMPLETE=1

echo "Created TEST-only, ad-hoc-signed, unnotarized artifact: $DMG"
