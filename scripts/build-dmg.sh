#!/usr/bin/env bash
# build-dmg.sh — local Release archive + .dmg builder
# Usage: ./scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
VERSION="${1:-dev}"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/iPScanner.xcarchive"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/iPScanner-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen"; exit 1; }
command -v create-dmg >/dev/null || { echo "create-dmg not found. brew install create-dmg"; exit 1; }

# All three registries, not just MA-L: OUILookup resolves a MAC against MA-S and MA-M before
# falling back to MA-L, so refreshing oui.txt alone left the two narrower registries stale and a
# local .dmg disagreeing with a CI-built one about the same MAC.
echo "==> Refreshing OUI databases (best effort)"
refresh_oui() {
  curl -fsSL --max-time 60 "$1" -o "$2" || echo "    (could not refresh $(basename "$2"), using bundled copy)"
}
refresh_oui https://standards-oui.ieee.org/oui/oui.txt     iPScanner/Resources/oui.txt
refresh_oui https://standards-oui.ieee.org/oui28/mam.txt   iPScanner/Resources/oui28.txt
refresh_oui https://standards-oui.ieee.org/oui36/oui36.txt iPScanner/Resources/oui36.txt

echo "==> xcodegen generate"
xcodegen generate

echo "==> Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$DMG_DIR"

echo "==> Archiving Release"
xcodebuild \
  -scheme iPScanner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  archive

APP_SRC="$ARCHIVE_PATH/Products/Applications/iPScanner.app"
[[ -d "$APP_SRC" ]] || { echo "build failed: $APP_SRC missing"; exit 1; }

cp -R "$APP_SRC" "$DMG_DIR/"

echo "==> Packaging .dmg"
create-dmg \
  --volname "iPScanner $VERSION" \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "iPScanner.app" 140 180 \
  --app-drop-link 380 180 \
  "$DMG_PATH" \
  "$DMG_DIR/" \
  || true

[[ -f "$DMG_PATH" ]] || { echo "create-dmg failed"; exit 1; }

echo
echo "✅ DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"
