# 04 · Vault cluster (3 nodes, HA) behind Nginx

## Goal
Run three Vault nodes with Raft storage and TLS, plus an Nginx load balancer that forwards port 8443 to all three.
Then initialise Vault and unseal each node.

Files used: `resources/vault/vault.hcl.tmpl`, `resources/nginx/nginx-vault.conf.tmpl`.

## Steps

1. Load the settings and render one config per node. Look at the `retry_join` blocks. They let each node find the others.

   ```bash
   source ./lab.env
   for n in 1 2 3; do
     ipvar=VAULT${n}_IP; mkdir -p .work/vault/vault-$n
     NODE_ID=vault-$n NODE_IP=${!ipvar} \
       envsubst '${NODE_ID} ${NODE_IP} ${VAULT1_IP} ${VAULT2_IP} ${VAULT3_IP}' \
       < resources/vault/vault.hcl.tmpl > .work/vault/vault-$n/vault.hcl
   done
   cat .work/vault/vault-1/vault.hcl
   ```

2. Start the three nodes:

   ```bash
   for n in 1 2 3; do
     ipvar=VAULT${n}_IP
     docker run -d --name vault-$n --hostname vault-$n --network kind --ip ${!ipvar} \
       -e VAULT_ADDR=https://127.0.0.1:8200 -e VAULT_CACERT=/vault/tls/ca.crt \
       -v "$WORK/vault/vault-$n:/vault/config:ro" -v "$WORK/tls:/vault/tls:ro" -v zt-vault-$n-data:/vault/file \
       $VAULT_IMAGE server
   done
   ```

3. Start Nginx. For now it only load-balances Vault. Step 11 adds the app front door.

   ```bash
   mkdir -p .work/nginx
   envsubst '${VAULT1_IP} ${VAULT2_IP} ${VAULT3_IP} ${VAULT_PORT}' < resources/nginx/nginx-vault.conf.tmpl > .work/nginx/nginx.conf
   docker run -d --name zt-nginx --network kind --ip $NGINX_IP \
     -p 127.0.0.1:$VAULT_PORT:$VAULT_PORT -p $HTTPS_PORT:443 -p $HTTP_PORT:80 \
     -v "$WORK/nginx:/etc/nginx/custom:ro" $NGINX_IMAGE nginx -c /etc/nginx/custom/nginx.conf -g 'daemon off;'
   ```

4. Initialise Vault once, on node 1. The lab uses 1 key share; production would use 5 shares with a threshold of 3, or auto-unseal.

   ```bash
   docker exec vault-1 vault operator init -key-shares=1 -key-threshold=1 -format=json > .work/vault-init.json
   chmod 600 .work/vault-init.json
   ```

   This file holds the root token and the unseal key. It is in `.gitignore`. Never commit it.

5. Unseal all three nodes. Wait a few seconds between nodes, so nodes 2 and 3 can join the Raft cluster first.

   ```bash
   KEY=$(jq -r '.unseal_keys_b64[0]' .work/vault-init.json)
   for n in 1 2 3; do docker exec vault-$n vault operator unseal "$KEY"; sleep 5; done
   ```

6. Re-load the settings, so `VAULT_TOKEN` is set, and add the helper:

   ```bash
   source ./lab.env
   vault() { docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault-1 vault "$@"; }
   ```

## Check

```bash
vault operator raft list-peers
curl -s --cacert .work/tls/lab-ca.crt https://127.0.0.1:$VAULT_PORT/v1/sys/health | jq '{initialized,sealed,standby}'
```

You see three peers (one leader, two followers), and Vault answers through Nginx with `sealed: false`.
The UI is at https://127.0.0.1:8443. Log in with the root token.

**After a reboot**, Vault starts sealed. Repeat step 5, or run `automated/04-vault.sh`.
