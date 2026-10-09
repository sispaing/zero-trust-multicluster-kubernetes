# 05 · Vault configuration

## Goal
Configure four things in Vault:
1. **PKI.** A root CA and an intermediate CA. These are the mesh root of trust that both clusters share.
2. **Policies.** Each identity can only do one job.
3. **Database secrets engine.** It creates short-lived PostgreSQL users.
4. **Kubernetes auth.** One mount per cluster, so pods can log in with their service account.

Files used: `resources/vault/policies/*.hcl`, `resources/vault/db-role-creation.sql`, `resources/k8s/vault-auth.yaml`.

## Steps

Load the settings and the helper first:

```bash
source ./lab.env
vault() { docker exec -i -e VAULT_TOKEN="$VAULT_TOKEN" vault-1 vault "$@"; }
```

### Part 1: PKI

1. Create the root CA (10 years) and save its certificate. Clients will trust this file.

   ```bash
   vault secrets enable pki
   vault secrets tune -max-lease-ttl=87600h pki
   vault write -field=certificate pki/root/generate/internal common_name="ZT Lab Mesh Root CA" ttl=87600h > /dev/null
   vault read -field=certificate pki/cert/ca > .work/mesh-root-ca.crt
   ```

2. Create the intermediate CA and have the root sign it. Day-to-day signing uses the intermediate, so the root key is rarely used.

   ```bash
   vault secrets enable -path=pki_int pki
   vault secrets tune -max-lease-ttl=43800h pki_int
   CSR=$(vault write -format=json pki_int/intermediate/generate/internal common_name="ZT Lab Mesh Intermediate CA" | jq -r .data.csr)
   SIGNED=$(printf '%s' "$CSR" | vault write -format=json pki/root/sign-intermediate csr=- format=pem_bundle ttl=43800h | jq -r .data.certificate)
   printf '%s' "$SIGNED" | vault write pki_int/intermediate/set-signed certificate=-
   ```

3. Create the role `mesh`. It allows SPIFFE URI SANs such as `spiffe://cluster.local/ns/kanban/sa/kanban-app`. Certificates last at most 72 hours.

   ```bash
   vault write pki_int/roles/mesh allow_any_name=true enforce_hostnames=false require_cn=false \
     allowed_uri_sans="spiffe://*" allow_ip_sans=true use_csr_common_name=true use_csr_sans=true key_type=any max_ttl=72h
   ```

### Part 2: Policies

4. Load the two least-privilege policies:

   ```bash
   cat resources/vault/policies/cert-manager.hcl resources/vault/policies/kanban-db.hcl
   vault policy write cert-manager - < resources/vault/policies/cert-manager.hcl
   vault policy write kanban-db    - < resources/vault/policies/kanban-db.hcl
   ```

### Part 3: Dynamic database credentials

5. Connect Vault to PostgreSQL. `verify-full` means Vault checks the Postgres certificate and hostname.

   ```bash
   vault secrets enable database
   vault write database/config/kanban plugin_name=postgresql-database-plugin allowed_roles=kanban-app \
     connection_url="postgresql://{{username}}:{{password}}@$PG_IP:5432/kanban?sslmode=verify-full&sslrootcert=/vault/tls/lab-ca.crt" \
     username=vaultadmin password="$VAULT_DB_ADMIN_PASSWORD"
   ```

   Optional hardening: run `vault write -force database/rotate-root/kanban`. After this, only Vault knows the `vaultadmin` password.

6. Create the role `kanban-app`. Each read creates a new Postgres user that lasts 1 hour (24 hours at most). The SQL it runs is in `resources/vault/db-role-creation.sql`.

   ```bash
   vault write database/roles/kanban-app db_name=kanban default_ttl=1h max_ttl=24h creation_statements=- \
     < resources/vault/db-role-creation.sql
   ```

### Part 4: Kubernetes auth (repeat for each cluster)

7. Run this block once with `c=$C1`, then again with `c=$C2`.

   ```bash
   c=$C1
   kubectl --context kind-$c apply -f resources/k8s/vault-auth.yaml
   sleep 3
   TOKEN=$(kubectl --context kind-$c -n kube-system get secret vault-auth-token -o jsonpath='{.data.token}' | base64 -d)
   KCA=$(kubectl --context kind-$c -n kube-system get secret vault-auth-token -o jsonpath='{.data.ca\.crt}' | base64 -d)
   API=$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' $c-control-plane)

   vault auth enable -path=kubernetes-$c kubernetes
   vault write auth/kubernetes-$c/config kubernetes_host="https://$API:6443" kubernetes_ca_cert="$KCA" token_reviewer_jwt="$TOKEN"

   vault write auth/kubernetes-$c/role/cert-manager \
     bound_service_account_names=vault-issuer bound_service_account_namespaces=cert-manager \
     audience="vault://vault-issuer" token_policies=cert-manager token_ttl=20m
   vault write auth/kubernetes-$c/role/kanban-app \
     bound_service_account_names=kanban-app bound_service_account_namespaces=kanban \
     token_policies=kanban-db token_ttl=1h
   ```

   Vault uses the `vault-auth` service account to call each cluster's TokenReview API. This is how it checks that a pod's token is real.

## Check

```bash
vault read database/creds/kanban-app
docker exec zt-postgres psql -U postgres -tAc "select rolname, rolvaliduntil from pg_roles where rolname like 'v-%'"
vault auth list
```

You get a new username like `v-root-kanban-a-...` with a password, and Postgres shows the same user with an expiry time.
