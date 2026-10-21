#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export QUICK_WINEPREFIX="${QUICK_WINEPREFIX:-$HOME/.local/share/amazon-quick/wineprefix}"
logdir="${XDG_STATE_HOME:-$HOME/.local/state}/amazon-quick"
mkdir -p "$logdir"

if ! "$here/setup-prefix.sh" "$QUICK_WINEPREFIX" >"$logdir/prefix-setup.log" 2>&1; then
  echo "amazon-quick: Wine prefix setup failed, see $logdir/prefix-setup.log" >&2
  exit 1
fi

# The Linux UI and the Windows helper both keep local state in ~/.quickwork.
mkdir -p "$HOME/.quickwork"
winhome="$QUICK_WINEPREFIX/drive_c/users/$USER"
if [[ -d "$winhome" ]]; then
  [[ -L "$winhome/.quickwork" ]] || rm -rf "$winhome/.quickwork"
  ln -sfn "$HOME/.quickwork" "$winhome/.quickwork"
fi

exec "$here/amazon-quick" --ozone-platform-hint=auto "$@"
