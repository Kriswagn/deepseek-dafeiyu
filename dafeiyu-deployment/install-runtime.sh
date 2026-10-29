#!/usr/bin/env bash
# Run as the ordinary Linux runtime user after cloning this whole repository.
set -euo pipefail
[[ $(id -u) != 0 ]] || { echo 'Run as the ordinary runtime user, not root.' >&2; exit 1; }
repo=$(cd "$(dirname "$0")/.." && pwd)
app="$repo/dafeiyu-bot"
target="$HOME/dafeiyu-bot"
[[ -f "$app/Package.swift" ]] || { echo 'Application source is missing.' >&2; exit 1; }
if [[ -e "$target" || -L "$target" ]]; then
  [[ $(readlink -f "$target") == "$app" ]] || { echo 'Existing runtime source differs; preserve it and follow the upgrade instructions.' >&2; exit 1; }
else
  ln -s "$app" "$target"
fi
mkdir -p "$HOME/deployment" "$HOME/qq-runtime/plugins"
for name in run-panel.sh stop-panel.sh get-panel-url.py read-token.py check-login.py provision-qq.sh; do
  install -m 700 "$repo/dafeiyu-deployment/$name" "$HOME/deployment/$name"
done
install -m 700 "$app/deploy/qq-container-entrypoint.sh" "$HOME/qq-runtime/qq-container-entrypoint.sh"
if [[ ! -e "$HOME/qq-runtime/config" ]]; then
  python3 "$app/scripts/init-qq-config.py" --directory "$HOME/qq-runtime/config"
else
  echo 'Existing QQ configuration retained; no tokens regenerated.'
fi
echo 'Helpers installed. Build the application, then provision the QQ container as root.'
