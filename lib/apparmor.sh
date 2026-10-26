#!/usr/bin/env bash
# Ubuntu 23.10 and later block unprivileged user namespaces unless an AppArmor
# profile allows them, and Electron's sandbox needs one. Without this profile
# the app aborts at launch: "The SUID sandbox helper binary was found, but is
# not configured correctly".
# Usage: apparmor.sh install|remove
set -euo pipefail
home_dir="$(readlink -m "${AMAZON_QUICK_HOME:-$HOME/.local/share/amazon-quick}")"
name="amazon-quick-$USER"
profile="/etc/apparmor.d/$name"
# Older versions installed one shared profile for every user. Two profiles that
# attach to the same binary make the app abort again, so it has to go.
legacy=/etc/apparmor.d/amazon-quick

unload() {
  [[ -f "$1" ]] || return 0
  sudo apparmor_parser -R "$1" 2>/dev/null || true
  sudo rm -f "$1"
}

case "${1:-}" in
  install)
    [[ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" == 1 ]] || exit 0
    # The path goes into the profile as-is, where quotes would end the rule and
    # glob or variable characters would widen what it attaches to.
    if [[ ! "$home_dir" =~ ^[A-Za-z0-9._/+\ -]+$ || ! "$USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: unsupported characters in $home_dir or user name $USER" >&2
      exit 1
    fi
    echo "==> Adding an AppArmor profile so the app's sandbox can start (needs sudo)" >&2
    unload "$legacy"
    sudo tee "$profile" >/dev/null <<EOF
abi <abi/4.0>,
include <tunables/global>

profile $name "$home_dir/app-*/amazon-quick" flags=(unconfined) {
  userns,

  include if exists <local/$name>
}
EOF
    sudo apparmor_parser -r "$profile"
    ;;
  remove)
    unload "$profile"
    unload "$legacy"
    ;;
  *)
    echo "usage: $0 install|remove" >&2
    exit 2
    ;;
esac
