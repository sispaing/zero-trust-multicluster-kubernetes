#!/usr/bin/env bash
# Checks tools, Docker, RAM, inotify limits and host ports.
source "$(dirname "$0")/lib.sh"
log "Checking required tools"
missing=0
for t in docker kind kubectl helm jq openssl envsubst curl; do
  if command -v "$t" >/dev/null; then ok "$t"; else bad "$t is missing"; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "Install the missing tools first (see manual/00-prerequisites.md)."; exit 1; }
docker info >/dev/null 2>&1 && ok "Docker is running" || { bad "Docker is not running or your user cannot use it"; exit 1; }

log "Checking memory"
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
[ "$mem_gb" -ge 14 ] && ok "${mem_gb} GB RAM" || echo "  Only ${mem_gb} GB RAM. The full lab needs about 12-16 GB."

log "Checking inotify limits"
w=$(sysctl -n fs.inotify.max_user_watches); i=$(sysctl -n fs.inotify.max_user_instances)
if [ "$w" -lt 524288 ] || [ "$i" -lt 512 ]; then
  bad "watches=$w instances=$i. Fix with:"
  echo "    echo -e 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/99-kind.conf && sudo sysctl --system"
else ok "inotify limits are fine"; fi

log "Checking host ports"
for p in "$HTTPS_PORT" "$HTTP_PORT" "$VAULT_PORT"; do
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$"; then bad "Port $p is in use"; else ok "Port $p is free"; fi
done
