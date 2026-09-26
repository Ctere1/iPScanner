#!/usr/bin/env bash
# Presentation only. The release pipeline signs/notarizes the finished image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 3 ]] || { echo 'Usage: create-dmg.sh APP OUTPUT_DMG VOLUME_NAME' >&2; exit 1; }
APP="$1"
DMG="$2"
VOLUME="$3"
[[ -d "$APP/Contents" ]] || { echo 'Application bundle missing' >&2; exit 1; }
[[ ! -e "$DMG" ]] || { echo 'Refusing to overwrite an existing disk image' >&2; exit 1; }
# An isolated environment keeps the build dependency out of system Python.
VENV="${DMG_TOOLS_VENV:-$ROOT/build/dmg-tools}"
if [[ ! -x "$VENV/bin/python3" ]]; then python3 -m venv "$VENV"; fi
"$VENV/bin/python3" -m pip install --disable-pip-version-check -r "$ROOT/scripts/requirements-dmg.txt"
"$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg-settings.py" \
  -D "app=$APP" -D "background=$ROOT/assets/dmg/background.png" "$VOLUME" "$DMG"
hdiutil verify "$DMG"
