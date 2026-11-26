#!/bin/bash
# Builds Lyrik and installs it to /Applications, replacing any earlier copy, then opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

DEST="/Applications/Lyrik.app"
echo "==> Quitting any running copy"
osascript -e 'tell application id "local.cadence.lyrics" to quit' >/dev/null 2>&1 || true
sleep 1

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto build/Lyrik.app "$DEST"

echo "==> Opening Lyrik"
open "$DEST" --args --open-window
echo "Done. Lyrik lives in your menu bar."
