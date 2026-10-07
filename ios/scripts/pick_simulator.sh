#!/usr/bin/env bash
# Affiche le nom du simulateur à utiliser : « iPhone 16 » s'il existe, sinon le premier iPhone disponible.
set -euo pipefail
list="$(xcrun simctl list devices available 2>/dev/null || true)"
if grep -q "    iPhone 16 (" <<<"$list"; then
  echo "iPhone 16"
  exit 0
fi
grep -o "    iPhone [^(]*" <<<"$list" | head -1 | sed -e 's/^ *//' -e 's/ *$//'
