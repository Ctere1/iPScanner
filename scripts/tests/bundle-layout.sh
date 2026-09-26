#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR=$(mktemp -d "${TMPDIR:-/tmp}/ipscanner-layout-test.XXXXXX")
trap 'rm -rf "$DIR"' EXIT
APP="$DIR/iPScanner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$ROOT/iPScanner/Resources/vendors.json" "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string iPScanner' "$APP/Contents/Info.plist" >/dev/null
printf '#!/bin/sh\necho gui\n' > "$APP/Contents/MacOS/iPScanner"
printf '#!/bin/sh\necho cli help\n' > "$APP/Contents/Helpers/ipscanner"
chmod +x "$APP/Contents/MacOS/iPScanner" "$APP/Contents/Helpers/ipscanner"
"$ROOT/scripts/check-bundle-layout.sh" "$APP"
echo 'PASS distinct GUI and CLI accepted'
cp "$APP/Contents/Helpers/ipscanner" "$APP/Contents/MacOS/iPScanner"
if "$ROOT/scripts/check-bundle-layout.sh" "$APP"; then exit 1; fi
echo 'PASS overwritten GUI rejected'
rm "$APP/Contents/Helpers/ipscanner"
if "$ROOT/scripts/check-bundle-layout.sh" "$APP"; then exit 1; fi
echo 'PASS missing helper rejected'
