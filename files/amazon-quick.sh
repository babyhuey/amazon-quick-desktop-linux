#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Fixed paths: Electron strips non-allowlisted environment variables before it
# starts the helper, so the helper can only find the prefix at this location.
prefix="$HOME/.local/share/amazon-quick/wineprefix"
logdir="$HOME/.local/state/amazon-quick"
mkdir -p "$logdir"

if ! "$here/setup-prefix.sh" "$prefix" >"$logdir/prefix-setup.log" 2>&1; then
  echo "amazon-quick: Wine prefix setup failed, see $logdir/prefix-setup.log" >&2
  exit 1
fi

# The Linux UI and the Windows helper both keep local state in ~/.quickwork.
mkdir -p "$HOME/.quickwork"
winhome="$prefix/drive_c/users/$USER"
if [[ -d "$winhome" ]]; then
  [[ -L "$winhome/.quickwork" ]] || rm -rf "$winhome/.quickwork"
  ln -sfn "$HOME/.quickwork" "$winhome/.quickwork"
fi

exec "$here/amazon-quick" --ozone-platform-hint=auto "$@"
