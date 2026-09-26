#!/usr/bin/env bash
# Only call after the final DMG is signed, notarized and stapled.
set -euo pipefail
DMG="${1:?Final DMG required}"
VERSION="${2:?Version required}"
DEST="${3:?Output directory required}"
: "${SPARKLE_BIN:?Path to the pinned Sparkle bin directory required}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
test -f "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --verbose=2 "$DMG"
mkdir -p "$DEST"
[[ ! -e "$DEST/$(basename "$DMG")" ]]
ditto "$DMG" "$DEST/$(basename "$DMG")"
cp "docs/release-notes-$VERSION.md" "$DEST/$(basename "${DMG%.dmg}").md"
KEY_ARGS=(--account ipscanner)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"); fi
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/canberkys/iPScanner/releases/download/v$VERSION/" \
    --link https://github.com/canberkys/iPScanner "$DEST"
python3 - "$DEST/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]); ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = root.findall('./channel/item')
assert items, 'No update generated'
for item in items:
    enc = item.find('enclosure')
    assert enc is not None and enc.get(ns+'edSignature'), 'Missing EdDSA signature'
    assert enc.get('url', '').startswith('https://github.com/canberkys/iPScanner/releases/download/'), 'Unexpected download host'
    assert int(enc.get('length','0')) > 0
print('Signed appcast generated. Publish the DMG before promoting this feed.')
PY
