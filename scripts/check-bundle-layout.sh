#!/usr/bin/env bash
# Usable before signing, in CI and after extracting a signed DMG.
set -euo pipefail
APP="${1:?Usage: check-bundle-layout.sh APP}"
GUI="$APP/Contents/MacOS/iPScanner"
CLI="$APP/Contents/Helpers/ipscanner"
test -x "$GUI"
test -x "$CLI"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")" == iPScanner ]]
! cmp -s "$GUI" "$CLI" || { echo 'GUI was overwritten by CLI (#10)' >&2; exit 1; }
"$CLI" --help >/dev/null

python3 - "$APP" <<'PYTHON'
import json, pathlib, sys
resources = pathlib.Path(sys.argv[1]) / 'Contents/Resources'
assert not any(resources.glob('oui*.txt')), 'Raw IEEE files must not be bundled'
index = json.loads((resources / 'vendors.json').read_text())
assert index['version'] == 1
for table, minimum in [('mal', 10000), ('mam', 1000), ('mas', 1000)]:
    assert len(index[table]) >= minimum, 'Missing or incomplete vendor index'
assert len(index['sources']) == 3
PYTHON
