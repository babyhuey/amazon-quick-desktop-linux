#!/usr/bin/env bash
# Rebuilds Amazon Quick when Amazon publishes a new Windows installer.
# Usage: update.sh [--force]
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
installer_url="https://desktop.downloads.quick.aws.com/windows/x64/Amazon-Quick.exe"
home_dir="${AMAZON_QUICK_HOME:-$HOME/.local/share/amazon-quick}"

notify() { command -v notify-send >/dev/null && notify-send -a "Amazon Quick" "$@" || true; }

latest="$(curl -fsSI "$installer_url" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '"')"
[[ -n "$latest" ]] || { echo "could not reach the upstream installer" >&2; exit 1; }
installed="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["etag"])' \
  "$home_dir/current/build-info.json" 2>/dev/null || true)"

if [[ "$latest" == "$installed" && "${1:-}" != --force ]]; then
  echo "Amazon Quick is up to date"
  exit 0
fi

echo "New upstream installer ($latest), rebuilding"
if "$repo/build.sh"; then
  version="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$home_dir/current/build-info.json")"
  notify "Amazon Quick updated to $version" "Restart the app to use the new version."
else
  notify -u critical "Amazon Quick update failed" "Run update.sh in a terminal to see why. The previous version still works."
  exit 1
fi
