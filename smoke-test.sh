#!/usr/bin/env bash
# Checks that a build's Windows helper starts under Wine and answers /health.
# With --electron, also launches the full app headlessly (needs xvfb-run).
# Uses its own Wine prefix, port and user-data dir, so it is safe to run while
# Amazon Quick is open.
#
# Usage: smoke-test.sh APP_DIR [--electron]
set -euo pipefail
app="$(readlink -f "$1")"
mode="${2:-}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/amazon-quick"
export QUICK_WINEPREFIX="$cache/smoke-prefix"
port=18790
tmp="$(mktemp -d)"
pid=""
cleanup() {
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  WINEPREFIX="$QUICK_WINEPREFIX" "$(command -v wineserver || ls /usr/lib/*/wine/wineserver /usr/lib/wine/wineserver64 2>/dev/null | head -1 || true)" -k 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "smoke test FAILED: $1" >&2
  for f in "$tmp"/*.log; do [[ -f "$f" ]] && { echo "--- $(basename "$f")" >&2; tail -40 "$f" >&2; }; done
  exit 1
}

"$app/setup-prefix.sh" "$QUICK_WINEPREFIX" >"$tmp/prefix.log" 2>&1 || fail "Wine prefix setup"

if [[ "$mode" != --electron ]]; then
  export QUICK_AGENT_LOG="$tmp/agent.log"
  echo smoke-test-token | QUICKWORK_CLOUD_MODE=1 QUICKWORK_BUILD_STAGE=prod APP_CHANNEL=prod PYTHONUTF8=1 \
    QUICKWORK_RESOURCES_PATH="$app/resources" \
    "$app/resources/agent/quickwork-agent" --outpost-only --manifest desktop --port "$port" >"$tmp/stdout.log" &
  pid=$!
  for _ in $(seq 1 120); do
    grep -q '^OUTPOST_PORT:' "$tmp/stdout.log" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || fail "helper exited before it was ready"
    sleep 1
  done
  grep -q '^OUTPOST_PORT:' "$tmp/stdout.log" || fail "helper not ready after 120s"
  curl -fsS -m 5 "http://127.0.0.1:$port/health" | grep -q '"status": *"ok"' || fail "/health did not return ok"
  echo "smoke test passed: helper ready, /health ok"
  exit 0
fi

command -v xvfb-run >/dev/null || fail "xvfb-run not found"
# A throwaway HOME keeps the test away from the real ~/.quickwork. The helper
# only looks for its prefix under $HOME, so point that path at the test prefix.
mkdir -p "$tmp/home/.local/share/amazon-quick"
ln -s "$QUICK_WINEPREFIX" "$tmp/home/.local/share/amazon-quick/wineprefix"
# Electron won't start its sandbox as root, which is how the container CI jobs run.
sandbox=()
[[ $EUID == 0 ]] && sandbox=(--no-sandbox)
HOME="$tmp/home" QUICKWORK_USER_DATA_DIR="$tmp/user-data" QUICKWORK_OUTPOST_PORT="$port" \
  timeout 150 xvfb-run -a "$app/amazon-quick.sh" "${sandbox[@]}" >"$tmp/electron.log" 2>&1 &
pid=$!
for _ in $(seq 1 140); do
  grep -q 'Window ready-to-show' "$tmp/electron.log" 2>/dev/null && grep -q 'Agent is ready' "$tmp/electron.log" && break
  kill -0 "$pid" 2>/dev/null || fail "app exited before it was ready"
  sleep 1
done
grep -q 'Agent is ready' "$tmp/electron.log" || fail "helper never became ready inside the app"
grep -q 'Window ready-to-show' "$tmp/electron.log" || fail "app window never rendered"
echo "smoke test passed: app window rendered, helper ready"
