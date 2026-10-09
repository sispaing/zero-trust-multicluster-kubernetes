#!/usr/bin/env bash
# Remove everything. Add --all to also delete .work (certs, Vault keys, Istio download).
source "$(dirname "$0")/lib.sh"
set +e
for c in "${CLUSTERS[@]}"; do kind delete cluster --name "$c"; done
docker rm -f vault-1 vault-2 vault-3 zt-nginx zt-postgres 2>/dev/null
docker volume rm zt-vault-1-data zt-vault-2-data zt-vault-3-data zt-pgdata 2>/dev/null
[ "${1:-}" = "--all" ] && rm -rf "$WORK" && echo "Removed $WORK"
echo "Cleanup complete."
