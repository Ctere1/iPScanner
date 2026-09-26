#!/usr/bin/env bash
# Sign the pinned Sparkle layout before signing the containing application.
set -euo pipefail
APP="${1:?Application path required}"
: "${SIGNING_IDENTITY:?Developer ID identity required}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for RELATIVE in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc; do
    test -e "$FRAMEWORK/$RELATIVE"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$FRAMEWORK/$RELATIVE"
done
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$FRAMEWORK"
codesign --verify --deep --strict "$FRAMEWORK"
