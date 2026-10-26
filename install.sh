#!/usr/bin/env bash
# Builds and installs Amazon Quick, then enables the daily update timer.
# Usage: install.sh [--no-timer]
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

"$repo/lib/apparmor.sh" install
"$repo/build.sh"

if [[ "${1:-}" != --no-timer ]]; then
  units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units"
  sed "s|@REPO@|$repo|" "$repo/systemd/amazon-quick-update.service.in" >"$units/amazon-quick-update.service"
  cp "$repo/systemd/amazon-quick-update.timer" "$units/"
  systemctl --user daemon-reload
  systemctl --user enable --now amazon-quick-update.timer
  echo "Daily update check enabled (systemctl --user list-timers amazon-quick-update.timer)"
fi

echo "Done. Start Amazon Quick from your app menu or run: amazon-quick"
