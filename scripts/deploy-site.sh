#!/usr/bin/env bash
# Assemble and deploy getmarkerapp.net: site/ + Sparkle artifacts.
# Run after scripts/notarize.sh and scripts/sparkle-release.sh.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="build/site"
SPARKLE="build/sparkle"

[ -f "$SPARKLE/appcast.xml" ] || {
  echo "!! Missing $SPARKLE/appcast.xml — run scripts/sparkle-release.sh first." >&2
  echo "   Deploying without it would break Check for Updates for installed apps." >&2
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R site/. "$OUT/"
cp "$SPARKLE/appcast.xml" "$OUT/"
cp "$SPARKLE"/*.dmg "$OUT/" 2>/dev/null || true
cp "$SPARKLE"/*.delta "$OUT/" 2>/dev/null || true
# Archived DMGs from past releases: keep old appcast/download links alive
# (stale feeds may still point installed apps at these exact files).
cp archive/*.dmg "$OUT/" 2>/dev/null || true

npx -y wrangler@latest deploy
