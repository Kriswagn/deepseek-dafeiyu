#!/usr/bin/env bash
set -euo pipefail
state="$HOME/.local/state/dafeiyu-deployment"
if [[ -f "$state/engine.pid" ]]; then
  read -r engine_pid <"$state/engine.pid"
  [[ "$engine_pid" =~ ^[0-9]+$ ]] || exit 1
  actual=$(readlink "/proc/$engine_pid/exe" || true)
  expected=$(readlink -f "$HOME/dafeiyu-bot/dist/dafeiyu-linux/dafeiyu")
  if [[ "$actual" == "$expected" ]]; then kill "$engine_pid"; fi
fi
