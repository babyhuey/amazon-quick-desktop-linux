#!/usr/bin/env bash
# Creates the Wine prefix the Windows helper runs in. Safe to re-run.
# Usage: setup-prefix.sh PREFIX
set -euo pipefail
prefix="$1"
[[ -f "$prefix/.amazon-quick-prefix" ]] && exit 0

mkdir -p "$prefix"
# Wine's credential store (where the sign-in token lives) is only obfuscated.
chmod 700 "$prefix"
export WINEPREFIX="$prefix" WINEDEBUG=-all
# Without these overrides wineboot waits on a hidden "install Mono/Gecko?" dialog.
export WINEDLLOVERRIDES="mscoree,mshtml="
# Ubuntu 26.04's wine package leaves wineserver out of $PATH; winetricks reads $WINESERVER.
WINESERVER="$(command -v wineserver || ls /usr/lib/*/wine/wineserver /usr/lib/wine/wineserver64 2>/dev/null | head -1 || true)"
export WINESERVER

wineboot -i
# Wine's builtin _locking() leaves errno unset, so Python's filelock raises
# instead of retrying. Microsoft's ucrtbase sets EACCES like real Windows.
winetricks -q ucrtbase2019

# The helper opens sign-in pages through winebrowser. Prefer a Chromium-family
# browser: Firefox containers and strict tracking protection break the flow.
browsers="xdg-open"
for b in chromium google-chrome-stable google-chrome microsoft-edge-stable brave-browser brave; do
  if command -v "$b" >/dev/null 2>&1; then browsers="$b,xdg-open"; break; fi
done
wine reg add 'HKCU\Software\Wine\WineBrowser' /v Browsers /t REG_SZ /d "$browsers" /f

"$WINESERVER" -w
touch "$prefix/.amazon-quick-prefix"
