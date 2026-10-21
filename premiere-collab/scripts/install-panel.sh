#!/bin/bash
# install-panel.sh - macOS twin of install-panel.ps1. Run on each laptop (no sudo needed).
#   bash scripts/install-panel.sh          # copy
#   bash scripts/install-panel.sh --link   # symlink to the repo (dev machine)
set -euo pipefail

id=com.hacklanta.premierecollab
src="$(cd "$(dirname "$0")/../panel" && pwd)"
root="$HOME/Library/Application Support/Adobe/CEP/extensions"
dst="$root/$id"

# 1. Allow unsigned panels. The manifest needs CSXS 11; newer Premiere builds read a higher key.
for v in 10 11 12 13; do
  defaults write "com.adobe.CSXS.$v" PlayerDebugMode 1
done
killall cfprefsd 2>/dev/null || true # flush the pref cache so Premiere sees it
echo "PlayerDebugMode = 1 (CSXS.10-13)"

# 2. Put the panel in the extensions folder
mkdir -p "$root"
rm -rf "$dst"
if [ "${1:-}" = "--link" ]; then
  ln -s "$src" "$dst" # shortcut: CEP following symlinks is unverified, drop --link if the panel is missing
  echo "Symlink: $dst -> $src"
else
  cp -R "$src" "$dst"
  echo "Copied panel to $dst"
fi

echo "Restart Premiere, then Window > Extensions > Tandem"
