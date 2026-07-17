#!/usr/bin/env bash
# check-layering.sh — fails if UI code leaks into CLI-shared code.
#
# The ipscanner tool compiles Models/ and Core/ alongside its own sources (see project.yml).
#
# Note this is an architectural rule, not a compile-time one: a macOS tool target links AppKit and
# Observation happily, so a view model in Core/ builds clean and simply ships dead weight into the
# CLI while making the type untestable without a UI. The compiler will never object. This grep is
# the only thing that will.
set -euo pipefail

cd "$(dirname "$0")/.."

# App/ and Views/ are deliberately absent: they are the layers allowed to import anything.
SHARED_DIRS=(iPScanner/Models iPScanner/Core)
FORBIDDEN='^import (SwiftUI|AppKit|Observation)'

status=0
for dir in "${SHARED_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  if hits=$(grep -rlE "$FORBIDDEN" "$dir" 2>/dev/null); then
    echo "error: UI framework imported in CLI-shared code:"
    echo "$hits" | sed 's/^/  /'
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  echo
  echo "Models/ and Core/ are compiled into the ipscanner CLI target, which has no UI frameworks."
  echo "Move the file to App/ (app-only) or drop the import."
  exit 1
fi

echo "✅ layering ok: no UI imports in ${SHARED_DIRS[*]}"
