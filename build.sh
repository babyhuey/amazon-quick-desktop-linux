#!/usr/bin/env bash
# Builds the Linux app from Amazon's official Windows installer and installs it
# under $AMAZON_QUICK_HOME (default ~/.local/share/amazon-quick).
#
# Environment:
#   AMAZON_QUICK_HOME          install root
#   AMAZON_QUICK_SKIP_DESKTOP  1 = don't install the launcher, desktop entry or URL handlers
#   AMAZON_QUICK_SKIP_SMOKE    1 = don't smoke-test the new build before switching to it
set -euo pipefail

repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
installer_url="https://desktop.downloads.quick.aws.com/windows/x64/Amazon-Quick.exe"
home_dir="${AMAZON_QUICK_HOME:-$HOME/.local/share/amazon-quick}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/amazon-quick"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

sevenzip="$(command -v 7z || command -v 7zz || true)"
[[ -n "$sevenzip" ]] || die "7-Zip not found (install 7zip or p7zip)"
for cmd in curl python3 sha256sum wine winepath winetricks cabextract; do
  command -v "$cmd" >/dev/null || die "$cmd not found"
done

mkdir -p "$cache" "$home_dir"
work="$(mktemp -d "$cache/build.XXXXXX")"
stage=""
trap 'rm -rf "$work" ${stage:+"$stage"}' EXIT

log "Checking the upstream installer"
etag="$(curl -fsSI "$installer_url" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}' | tr -d '"')"
[[ -n "$etag" ]] || die "could not read the installer ETag"
installer="$cache/Amazon-Quick-$etag.exe"
if [[ ! -f "$installer" ]]; then
  log "Downloading the installer (about 600 MB)"
  curl -fsSL --retry 3 -o "$installer.part" "$installer_url"
  mv "$installer.part" "$installer"
  find "$cache" -maxdepth 1 -name 'Amazon-Quick-*.exe' ! -name "Amazon-Quick-$etag.exe" -delete
fi

log "Extracting the installer"
"$sevenzip" e -y -o"$work" "$installer" '$PLUGINSDIR/app-64.7z' >/dev/null
[[ -f "$work/app-64.7z" ]] || die "app-64.7z not found in the installer; the installer layout changed"
"$sevenzip" x -y -o"$work/win" "$work/app-64.7z" >/dev/null
win="$work/win"
res="$win/resources"
for f in "$res/app.asar" "$res/agent.zip" "$win/Amazon Quick.exe"; do
  [[ -f "$f" ]] || die "missing $f; the installer layout changed"
done

version="$(python3 -I "$repo/lib/asar.py" "$res/app.asar" cat package.json \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
electron="$(grep -aoE -m1 'Electron/[0-9]+\.[0-9]+\.[0-9]+' "$win/Amazon Quick.exe" | head -1 | cut -d/ -f2)"
[[ -n "$version" && -n "$electron" ]] || die "could not read the app or Electron version"
log "Amazon Quick $version, Electron $electron"

ezip="$cache/electron-v$electron-linux-x64.zip"
if [[ ! -f "$ezip" ]]; then
  log "Downloading Electron $electron"
  base="https://github.com/electron/electron/releases/download/v$electron"
  curl -fsSL --retry 3 -o "$ezip.part" "$base/electron-v$electron-linux-x64.zip"
  curl -fsSL "$base/SHASUMS256.txt" | grep " \*\?electron-v$electron-linux-x64.zip\$" \
    | sed "s|electron-v$electron-linux-x64.zip|$ezip.part|" | sha256sum -c --quiet - \
    || die "Electron checksum mismatch"
  mv "$ezip.part" "$ezip"
fi

out="$home_dir/app-$version"
stage="$home_dir/.app-$version.tmp"
rm -rf "$stage"
mkdir -p "$stage"
log "Assembling $out"
"$sevenzip" x -y -o"$stage" "$ezip" >/dev/null
mv "$stage/electron" "$stage/amazon-quick"
rm -f "$stage/resources/default_app.asar"

cp "$res/app.asar" "$stage/resources/"
for d in app.asar.unpacked bin proxy-lep; do
  [[ -e "$res/$d" ]] && cp -r "$res/$d" "$stage/resources/"
done
# koffi only ships Windows builds and is only loaded on Windows.
rm -rf "$stage/resources/app.asar.unpacked/node_modules/koffi/build"

mkdir -p "$stage/resources/agent"
python3 -I "$repo/lib/unzip_backslash.py" "$res/agent.zip" "$stage/resources/agent"
for f in quickwork-agent.exe _internal/playwright/driver/node.exe; do
  [[ -f "$stage/resources/agent/$f" ]] || die "agent/$f missing; the helper layout changed"
done
install -m755 "$repo/files/quickwork-agent" "$stage/resources/agent/quickwork-agent"
install -m755 "$repo/files/amazon-quick.sh" "$repo/files/setup-prefix.sh" "$stage/"
python3 -I "$repo/lib/asar.py" "$res/app.asar" extract 'dist/renderer/assets/icon-*.png' "$stage/amazon-quick.png"

cat >"$stage/build-info.json" <<EOF
{"version": "$version", "electron": "$electron", "etag": "$etag", "built_at": "$(date -u +%FT%TZ)"}
EOF

if [[ "${AMAZON_QUICK_SKIP_SMOKE:-0}" != 1 ]]; then
  log "Smoke-testing the new build"
  "$repo/smoke-test.sh" "$stage"
fi

rm -rf "$out"
mv "$stage" "$out"
ln -sfn "app-$version" "$home_dir/current.tmp"
mv -T "$home_dir/current.tmp" "$home_dir/current"

# Keep the previous build so a running copy isn't deleted out from under it.
find "$home_dir" -maxdepth 1 -name 'app-*' -type d -printf '%T@ %p\n' | sort -rn | tail -n +3 \
  | cut -d' ' -f2- | xargs -r rm -rf

if [[ "${AMAZON_QUICK_SKIP_DESKTOP:-0}" != 1 ]]; then
  log "Installing the launcher and desktop entry"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  ln -sfn "$home_dir/current/amazon-quick.sh" "$HOME/.local/bin/amazon-quick"
  sed -e "s|@EXEC@|$HOME/.local/bin/amazon-quick|" -e "s|@ICON@|$home_dir/current/amazon-quick.png|" \
    "$repo/files/amazon-quick.desktop.in" >"$HOME/.local/share/applications/amazon-quick.desktop"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  xdg-mime default amazon-quick.desktop x-scheme-handler/amazonquick x-scheme-handler/awsquick 2>/dev/null || true
fi

log "Installed Amazon Quick $version"
