#!/usr/bin/env bash
# 3-node Vault (Raft, TLS) behind Nginx; initialise and unseal. Re-run after a reboot to unseal.
source "$(dirname "$0")/lib.sh"
for n in 1 2 3; do
  name="vault-$n"; ipvar="VAULT${n}_IP"; ip="${!ipvar}"
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then docker start "$name" >/dev/null; continue; fi
  log "Starting $name at $ip"
  mkdir -p "$WORK/vault/$name"
  NODE_ID="$name" NODE_IP="$ip" render "$RES/vault/vault.hcl.tmpl" NODE_ID NODE_IP VAULT1_IP VAULT2_IP VAULT3_IP > "$WORK/vault/$name/vault.hcl"
  docker run -d --name "$name" --hostname "$name" --network kind --ip "$ip" \
    -e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/ca.crt \
    -v "$WORK/vault/$name:/vault/config:ro" -v "$WORK/tls:/vault/tls:ro" -v "zt-$name-data:/vault/file" \
    "$VAULT_IMAGE" server >/dev/null
done

mkdir -p "$WORK/nginx"
[ -f "$WORK/nginx/nginx.conf" ] || render "$RES/nginx/nginx-vault.conf.tmpl" VAULT1_IP VAULT2_IP VAULT3_IP VAULT_PORT > "$WORK/nginx/nginx.conf"
if ! docker ps -a --format '{{.Names}}' | grep -qx zt-nginx; then
  log "Starting Nginx at $NGINX_IP"
  docker run -d --name zt-nginx --network kind --ip "$NGINX_IP" \
    -p "127.0.0.1:$VAULT_PORT:$VAULT_PORT" -p "$HTTPS_PORT:443" -p "$HTTP_PORT:80" \
    -v "$WORK/nginx:/etc/nginx/custom:ro" "$NGINX_IMAGE" nginx -c /etc/nginx/custom/nginx.conf -g 'daemon off;' >/dev/null
else docker start zt-nginx >/dev/null; fi

wait_up() { for _ in $(seq 1 60); do rc=0; docker exec "$1" vault status >/dev/null 2>&1 || rc=$?; { [ $rc -eq 0 ] || [ $rc -eq 2 ]; } && return 0; sleep 2; done; docker logs --tail 30 "$1"; exit 1; }
wait_up vault-1
if [ "$(docker exec vault-1 vault status -format=json 2>/dev/null | jq -r .initialized || true)" != "true" ]; then
  log "Initialising Vault (lab: 1 key share)"
  docker exec vault-1 vault operator init -key-shares=1 -key-threshold=1 -format=json > "$WORK/vault-init.json"
  chmod 600 "$WORK/vault-init.json"
fi
KEY=$(jq -r '.unseal_keys_b64[0]' "$WORK/vault-init.json")
for n in 1 2 3; do
  wait_up "vault-$n"
  if [ "$(docker exec "vault-$n" vault status -format=json 2>/dev/null | jq -r .sealed || true)" = "true" ]; then
    log "Unsealing vault-$n"; sleep 3; retry docker exec "vault-$n" vault operator unseal "$KEY" >/dev/null
  fi
  sleep 5
done
retry vault_cli operator raft list-peers
