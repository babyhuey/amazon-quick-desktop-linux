#!/usr/bin/env bash
# Removes the app, launcher, desktop entry and update timer.
# With --purge, also removes the Wine prefix (including the saved sign-in),
# the app's settings and its local data in ~/.quickwork.
set -euo pipefail
home_dir="${AMAZON_QUICK_HOME:-$HOME/.local/share/amazon-quick}"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

systemctl --user disable --now amazon-quick-update.timer 2>/dev/null || true
rm -f "$units/amazon-quick-update.service" "$units/amazon-quick-update.timer"
systemctl --user daemon-reload 2>/dev/null || true

rm -f "$HOME/.local/bin/amazon-quick" "$HOME/.local/share/applications/amazon-quick.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
find "$home_dir" -maxdepth 1 \( -name 'app-*' -o -name '.app-*' -o -name current \) -exec rm -rf {} + 2>/dev/null || true
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/amazon-quick"

if [[ "${1:-}" == --purge ]]; then
  rm -rf "$home_dir" "${XDG_STATE_HOME:-$HOME/.local/state}/amazon-quick" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/quickwork" "$HOME/.quickwork"
  echo "Removed Amazon Quick and all of its data"
else
  echo "Removed Amazon Quick. Your sign-in and settings are kept; run with --purge to delete them."
fi
