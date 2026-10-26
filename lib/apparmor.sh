#!/usr/bin/env bash
# Ubuntu 23.10 and later block unprivileged user namespaces unless an AppArmor
# profile allows them, and Electron's sandbox needs one. Without this profile
# the app aborts at launch: "The SUID sandbox helper binary was found, but is
# not configured correctly".
# Usage: apparmor.sh install|remove
set -euo pipefail
profile=/etc/apparmor.d/amazon-quick
# @{HOME} covers every user's default install, so one shared profile works for all of them.
if [[ -n "${AMAZON_QUICK_HOME:-}" ]]; then
  binary="\"$(readlink -m "$AMAZON_QUICK_HOME")/app-*/amazon-quick\""
else
  binary="@{HOME}/.local/share/amazon-quick/app-*/amazon-quick"
fi

case "${1:-}" in
  install)
    [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" == 1 ]] || exit 0
    echo "==> Adding an AppArmor profile so the app's sandbox can start (needs sudo)" >&2
    sudo tee "$profile" >/dev/null <<EOF
abi <abi/4.0>,
include <tunables/global>

profile amazon-quick $binary flags=(unconfined) {
  userns,

  include if exists <local/amazon-quick>
}
EOF
    sudo apparmor_parser -r "$profile"
    ;;
  remove)
    [[ -f "$profile" ]] || exit 0
    sudo apparmor_parser -R "$profile" 2>/dev/null || true
    sudo rm -f "$profile"
    ;;
  *)
    echo "usage: $0 install|remove" >&2
    exit 2
    ;;
esac
