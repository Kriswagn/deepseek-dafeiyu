#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run as root inside Dafeiyu-Ubuntu' >&2; exit 1; }
runtime_user=${DAFEIYU_RUNTIME_USER:-dafeiyu}
runtime_home=$(getent passwd "$runtime_user" | cut -d: -f6)
[[ -n "$runtime_home" && -d "$runtime_home" ]] || { echo 'Runtime user home not found' >&2; exit 1; }
runtime=${DAFEIYU_RUNTIME_DIR:-$runtime_home/qq-runtime}
image=mlikiowa/napcat-docker@sha256:69c5ca84ec226d658d0d5cd19997c6c89169da3206faa2948c2dc67d669b6406
docker run --rm --network none --entrypoint /bin/sh "$image" -c \
  'test "$(id -u)" = 0 && id napcat >/dev/null && test -x /opt/QQ/qq && command -v gosu >/dev/null && command -v Xvfb >/dev/null && printf "%s  %s\n" 6801f93e533846cea05f4f531874a0e84371ab2331c5585b57cd7e3b869cf96b /app/NapCat.Shell.zip | sha256sum -c -'
for name in onebot11.json webui.json napcat.json; do test -s "$runtime/config/$name"; done
test -s "$runtime/qq-container-entrypoint.sh"
mkdir -p "$runtime/plugins"
if ! docker container inspect qq-ai >/dev/null 2>&1; then
  docker create --name qq-ai --hostname qq-ai-runtime --init \
    --restart=no --memory=2g --cpus=2 --pids-limit=512 \
    --security-opt=no-new-privileges:true \
    -p 127.0.0.1:6099:6099 -p 127.0.0.1:3001:3001 \
    --mount "type=bind,source=$runtime/config,target=/app/napcat/config" \
    --mount "type=bind,source=$runtime/plugins,target=/app/napcat/plugins" \
    --mount "type=bind,source=$runtime/qq-container-entrypoint.sh,target=/qq-entrypoint.sh,readonly" \
    --mount type=volume,source=qq-ai-data,target=/app/.config/QQ \
    --log-driver=local --log-opt max-size=1m --log-opt max-file=2 \
    --entrypoint /bin/bash "$image" /qq-entrypoint.sh >/dev/null
fi
docker start qq-ai
docker ps --filter name=qq-ai --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
