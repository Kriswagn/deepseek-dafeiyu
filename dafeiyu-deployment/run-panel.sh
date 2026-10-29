#!/usr/bin/env bash
set -euo pipefail
umask 077
state="$HOME/.local/state/dafeiyu-deployment"
mkdir -p "$state"
exec 9>"$state/engine.lock"
if ! flock -n 9; then
  grep -m1 '^QQ_CONTROL_URL=' "$state/panel.log"
  exit 0
fi
cd "$HOME/dafeiyu-bot"
bash scripts/start-linux.sh >"$state/panel.log" 2>&1 &
engine_pid=$!
printf '%s\n' "$engine_pid" >"$state/engine.pid"
cleanup() { kill "$engine_pid" 2>/dev/null || true; rm -f "$state/engine.pid"; }
trap cleanup EXIT
trap 'exit 0' INT TERM
ready=0
for ((n=0;n<80;n++)); do
  if grep -m1 '^QQ_CONTROL_URL=' "$state/panel.log"; then ready=1; break; fi
  kill -0 "$engine_pid" 2>/dev/null || { cat "$state/panel.log"; exit 1; }
  sleep 0.25
done
[[ "$ready" == 1 ]] || { echo 'Panel startup timed out' >&2; exit 1; }
wait "$engine_pid"
